defmodule ReqClientCredentials do
  @moduledoc """
  `Req` plugin for [OAuth 2.0 client credentials flow][rfc] authentication. The
  access token will be cached and reused for subsequent requests, if the
  response to the `:url` returns a 401 response then this plugin will refresh
  the access token (only refreshes one time). If an `:audience` is included in
  `:client_credentials_params` then this plugin will only run if the schema,
  host, and port of the `:url` match that of the `:audience`.

  [rfc]: https://datatracker.ietf.org/doc/html/rfc6749#section-4.4
  """

  @doc """
  Runs the plugin.

  ## Usage

      req =
        Req.new(
          client_credentials_params: [
            audience: "https://api.example.com",
            client_id: System.get_env("EXAMPLE_CLIENT_ID"),
            client_secret: System.get_env("EXAMPLE_CLIENT_SECRET")
          ],
          client_credentials_url: "https://auth.example.com/oauth/token",
        )
        |> ReqClientCredentials.attach()
      Req.get!(req, url: "https://api.example.com/path")
      #=> %Req.Response{}
  """
  def attach(%Req.Request{} = req, opts \\ []) do
    req
    |> Req.Request.register_options([
      :client_credentials_params,
      :client_credentials_url
    ])
    |> Req.Request.merge_options(opts)
    |> Req.Request.append_request_steps(client_credentials: &auth/1)
    |> Req.Request.prepend_response_steps(client_credentials: &check_response/1)
    |> Req.Request.merge_options(retry: &retry/2)
    |> Req.Request.put_private(:client_credentials_refreshed?, false)
    |> Req.Request.put_private(:client_credentials_retry?, false)
    |> Req.Request.put_private(:orig_retry, Req.Request.get_option(req, :retry))
  end

  defp auth(request) do
    with false <- skip?(request),
         params <- auth_params(request),
         true <- auth_fetch_token?(request, params),
         request <- Req.Request.put_private(request, :client_credentials_params, params),
         {:ok, {token, type}} <- fetch_token(request) do
      Req.Request.put_header(request, "authorization", type <> " " <> token)
    else
      {_request, _response_or_exception} = result -> result
      _other -> request
    end
  end

  defp auth_fetch_token?(request, params) do
    case Keyword.get(params, :audience) do
      nil ->
        true

      audience ->
        uri = URI.new!(audience)

        uri.scheme == request.url.scheme and uri.host == request.url.host and
          uri.port == request.url.port
    end
  end

  defp auth_params(request) do
    Keyword.merge(
      [grant_type: "client_credentials"],
      Req.Request.get_option(request, :client_credentials_params, [])
    )
  end

  @doc false
  def bust_cache(request) do
    :persistent_term.erase({__MODULE__, request.url.host})
  end

  defp check_response({request, response}) when response.status == 401 do
    if Req.Request.get_private(request, :client_credentials_refreshed?) do
      {Req.Request.put_private(request, :client_credentials_retry?, false), response}
    else
      case request_token(request) do
        {:ok, {token, type}} ->
          request =
            request
            |> Req.Request.put_header("authorization", type <> " " <> token)
            |> Req.Request.put_private(:client_credentials_refreshed?, true)
            |> Req.Request.put_private(:client_credentials_retry?, true)

          {request, response}

        _ ->
          {request, response}
      end
    end
  end

  defp check_response({request, response}), do: {request, response}

  @doc false
  def fetch_cache(request) do
    with data when is_tuple(data) <- :persistent_term.get({__MODULE__, request.url.host}, :error) do
      {:ok, data}
    end
  end

  defp fetch_token(request) do
    with :error <- fetch_cache(request) do
      request_token(request)
    end
  end

  defp request_token(request) do
    options =
      Map.drop(request.options, [
        :body,
        :client_credentials_params,
        :client_credentials_url,
        :form,
        :json
      ])

    auth_req =
      Req.Request.new(url: Req.Request.fetch_option!(request, :client_credentials_url))
      |> Req.Request.append_request_steps(
        Keyword.drop(request.request_steps, [:client_credentials])
      )
      |> Req.Request.append_response_steps(
        Keyword.drop(request.response_steps, [:client_credentials])
      )
      |> Req.Request.append_error_steps(request.error_steps)
      |> Req.Request.register_options(Enum.to_list(request.registered_options))
      |> Req.Request.merge_options(Map.to_list(options))

    auth_req =
      case Req.Request.get_private(auth_req, :orig_retry) do
        nil -> auth_req
        retry -> Req.Request.merge_options(auth_req, retry: retry)
      end

    with {:ok, %{body: %{"access_token" => token, "token_type" => type}}} <-
           Req.post(auth_req, form: Req.Request.get_private(request, :client_credentials_params)) do
      data = {token, type}
      write_cache(request, data)
      {:ok, data}
    else
      {:ok, %Req.Response{} = response} -> {request, response}
      _ -> :error
    end
  end

  defp retry(request, %Req.Response{} = response) do
    response.status == 401 and Req.Request.get_private(request, :client_credentials_retry?)
  end

  defp retry(request, _response_or_exception), do: Req.Request.get_private(request, :orig_retry)

  defp skip?(request) do
    !Req.Request.get_option(request, :client_credentials_url)
  end

  @doc false
  def write_cache(request, data) do
    :persistent_term.put({__MODULE__, request.url.host}, data)
  end
end
