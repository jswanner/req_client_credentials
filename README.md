# ReqClientCredentials

`Req` plugin for [OAuth 2.0 client credentials flow][rfc] authentication. The
access token will be cached and reused for subsequent requests, if the
response to the `:url` returns a 401 response then this plugin will refresh
the access token (only refreshes one time). If an `:audience` is included in
`:client_credentials_params` then this plugin will only run if the schema,
host, and port of the `:url` match that of the `:audience`.

## Usage

```elixir
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
```

[rfc]: https://datatracker.ietf.org/doc/html/rfc6749#section-4.4
