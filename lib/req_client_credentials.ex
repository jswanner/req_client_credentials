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
         true <- auth_fetch_token?(request, params) do
      request = Req.Request.put_private(request, :client_credentials_params, params)
      {token, type} = fetch_token!(request)
      Req.Request.put_header(request, "authorization", type <> " " <> token)
    else
      _ -> request
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
      {token, type} = request_token!(request)

      request =
        request
        |> Req.Request.put_header("authorization", type <> " " <> token)
        |> Req.Request.put_private(:client_credentials_refreshed?, true)
        |> Req.Request.put_private(:client_credentials_retry?, true)

      {request, response}
    end
  end

  defp check_response({request, response}), do: {request, response}

  defp fetch_token!(request) do
    read_cache(request) || request_token!(request)
  end

  @doc false
  def read_cache(request) do
    :persistent_term.get({__MODULE__, request.url.host}, nil)
  end

  defp request_token!(request) do
    req =
      %{
        request
        | current_request_steps: Keyword.keys(request.request_steps) -- [:client_credentials],
          request_steps: request.request_steps -- [client_credentials: &auth/1],
          response_steps: request.response_steps -- [client_credentials: &check_response/1]
      }

    req =
      if retry = Req.Request.get_private(req, :orig_retry) do
        Req.merge(req, retry: retry)
      else
        Req.Request.delete_option(req, :retry)
      end

    %{body: %{"access_token" => token, "token_type" => type}} =
      req
      |> Req.Request.drop_options([:client_credentials_params, :client_credentials_url, :params])
      |> Req.merge(
        form: Req.Request.get_private(request, :client_credentials_params),
        url: Req.Request.fetch_option!(request, :client_credentials_url)
      )
      |> Req.post!()

    {token, type}
    |> tap(&write_cache(request, &1))
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
