# ReqClientCredentials

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

## Usage

```elixir
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
```

[rfc]: https://datatracker.ietf.org/doc/html/rfc6749#section-4.4
