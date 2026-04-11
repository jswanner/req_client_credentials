defmodule ReqClientCredentials do
  @moduledoc """
  `Req` plugin for [OAuth 2.0 client credentials flow][rfc] authentication. This
  plugin accepts all the options of `Req` itself under the `:client_credentials`
  key. The access token will be cached and reused for subsequent requests, if
  the response to the authenticated `:url` returns a 401 response then this
  plugin will refresh the access token (only refreshes one time). If an
  `:audience` is included in `:form` or `:json` option for `:client_credentials`
  then this plugin will only run if the host and port of the authenticated
  `:url` match that of the `:audience`. The `:url` option within
  `:client_credentials` is the URL this plugin will make a POST request to for
  creating a bearer token.

  [rfc]: https://datatracker.ietf.org/doc/html/rfc6749#section-4.4
  """

  defguardp validated_request?(request)
            when is_tuple(request.private.client_credentials_data) and
                   tuple_size(request.private.client_credentials_data) == 3

  @doc """
  Runs the plugin.

  ## Usage

      Req.new(url: "https://api.example.com/path")
      |> ReqClientCredentials.attach()
      |> Req.get!(
        client_credentials: [
          form: [
            audience: "https://api.example.com",
            client_id: System.get_env("EXAMPLE_CLIENT_ID"),
            client_secret: System.get_env("EXAMPLE_CLIENT_SECRET")
          ],
          url: "https://auth.example.com/oauth/token",
        ]
      )
      #=> %Req.Response{}
  """
  def attach(%Req.Request{} = req, opts \\ []) do
    req
    |> Req.Request.register_options([:client_credentials])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(client_credentials: &auth/1)
    |> Req.Request.prepend_response_steps(client_credentials: &check_response/1)
  end

  defp auth(request) do
    options = Req.Request.get_option(request, :client_credentials, [])

    with {:ok, request} <- validate(request, options),
         {:ok, token} <- fetch_token(request) do
      request
      |> Req.Request.put_header("authorization", "Bearer " <> token)
      |> Req.Request.put_private(:client_credentials_refreshed?, false)
    else
      {_request, _response_or_exception} = result -> result
      _other -> request
    end
  end

  @doc false
  def bust_cache(request) do
    :persistent_term.erase(cache_key(request))
  end

  defp cache_key(request) do
    request = Req.Steps.put_base_url(request)

    {
      __MODULE__,
      request.url.host,
      Req.Request.fetch_option!(request, :client_credentials)
    }
  end

  defp check_response({request, response})
       when validated_request?(request) and response.status == 401 do
    if Req.Request.get_private(request, :client_credentials_refreshed?) do
      {request, response}
    else
      case request_token(request) do
        {:ok, token} ->
          %{request | halted: false}
          |> Req.Request.put_header("authorization", "Bearer " <> token)
          |> Req.Request.put_private(:client_credentials_refreshed?, true)
          |> Req.Request.run_request()

        _ ->
          {request, response}
      end
    end
  end

  defp check_response({request, response}), do: {request, response}

  @doc false
  def fetch_cache(request) do
    with token when is_binary(token) <- :persistent_term.get(cache_key(request), :error) do
      {:ok, token}
    end
  end

  defp fetch_token(request) do
    with :error <- fetch_cache(request) do
      request_token(request)
    end
  end

  defp request_token(request) do
    {options, encoding, params} = Req.Request.get_private(request, :client_credentials_data)
    options = if encoding, do: put_in(options[encoding], params), else: options

    auth_req =
      Req.Request.new()
      |> Req.Request.append_request_steps(
        Keyword.drop(request.request_steps, [:client_credentials])
      )
      |> Req.Request.append_response_steps(
        Keyword.drop(request.response_steps, [:client_credentials])
      )
      |> Req.Request.append_error_steps(request.error_steps)
      |> Req.Request.register_options(Enum.to_list(request.registered_options))
      |> Req.Request.merge_options(
        request.options
        |> Map.drop([:body, :client_credentials, :form, :json])
        |> Map.to_list()
      )

    with {:ok, %{body: %{"access_token" => token}}} <- Req.post(auth_req, options) do
      write_cache(request, token)
      {:ok, token}
    else
      {:ok, %Req.Response{} = response} -> {request, response}
      _ -> :error
    end
  end

  defp validate(request, options) do
    with :ok <- validate_url(options),
         {:ok, {encoding, params}} <- validate_params(options),
         :ok <- validate_audience(request, params) do
      {:ok,
       Req.Request.put_private(request, :client_credentials_data, {options, encoding, params})}
    else
      _ -> :error
    end
  end

  defp validate_audience(request, params) do
    case get_in(params, [:audience]) do
      nil ->
        :ok

      audience ->
        uri = URI.new!(audience)
        if uri.host == request.url.host and uri.port == request.url.port, do: :ok, else: :error
    end
  end

  defp validate_params(options) do
    {encoding, params} =
      cond do
        Keyword.has_key?(options, :form) -> {:form, options[:form]}
        Keyword.has_key?(options, :json) -> {:json, options[:json]}
        true -> {nil, []}
      end

    {:ok, {encoding, put_in(params, [:grant_type], "client_credentials")}}
  end

  defp validate_url(options) do
    case get_in(options, [:url]) do
      url when is_binary(url) -> :ok
      _ -> :error
    end
  end

  @doc false
  def write_cache(request, token) do
    :persistent_term.put(cache_key(request), token)
  end
end
