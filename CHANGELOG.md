# CHANGELOG

## v0.2.4 (2026-06-11)

  * Allows other grant type to be specified by the caller, grant type of
  `client_credentials` will be injected if missing in `:form` or `:json` options

## v0.2.3 (2026-04-11)

  * Fix cache key element when `:base_url` is used
  * Reruns request directly instead of using Req's retry step

## v0.2.2 (2026-04-06)

  * Fix ignore responses of requests that were ignored

## v0.2.1 (2026-04-06)

  * Fix fully resolve request URL before comparison with audience

## v0.2.0 (2026-04-06)

Overhaul of options for `ReqClientCredentials`, it now accepts all options `Req`
supports under the `:client_credentials` key. This is a **breaking change** as
the previous `:client_credentials_params` and `:client_credentials_url` are no
longer supported.

Where you previously configured ReqClientCredentials along the lines of:

```elixir
Req.new(url: "https://api.example.com/path")
|> ReqClientCredentials.attach()
|> Req.get!(
  client_credentials_params: [
    client_id: System.get_env("EXAMPLE_CLIENT_ID"),
    client_secret: System.get_env("EXAMPLE_CLIENT_SECRET")
  ],
  client_credentials_url: "https://auth.example.com/oauth/token"
)
```

That will now need to be done as:

```elixir
Req.new(url: "https://api.example.com/path")
|> ReqClientCredentials.attach()
|> Req.get!(
  client_credentials: [
    form: [
      client_id: System.get_env("EXAMPLE_CLIENT_ID"),
      client_secret: System.get_env("EXAMPLE_CLIENT_SECRET")
    ],
    url: "https://auth.example.com/oauth/token",
  ]
)
```

Note the use of `:form` to specify the body of the POST request to the
authorization server. Also, `grant_type: "client_credentials"` will continue to
be automatically injected into the body of the request, as long as `:form` or
`:json` are given within the `:client_credentials` option.

This change was made in order to make ReqClientCredentials more flexible with
how it makes the request for the access token. For instance, if your
authorization server uses basic auth, you can use Req's `:auth` option for that:

```elixir
Req.new(url: "https://api.example.com/path")
|> ReqClientCredentials.attach()
|> Req.get!(
  client_credentials: [
    auth: {:basic, "username:password" },
    form: [scope: "..."],
    url: "https://auth.example.com/oauth/token",
  ]
)
```

  * **(BREAKING CHANGE)** Drops `:client_credentials_params` and
  `:client_credentials_url` options in favor of any option Req supports under
  the `:client_credentials` key.

## v0.1.5 (2025-10-10)

  * Include client credentials URL & params in cache key.
  * Remove checking of URI scheme when determining whether to run.

## v0.1.4 (2025-09-17)

  * Fix incorrect content-type in token request by building new request.

## v0.1.3 (2025-07-31)

  * Fix inclusion of client credential params in access token request.

## v0.1.2 (2025-07-30)

  * Improve handling of failed token requests.

## v0.1.1 (2025-07-16)

  * Plugin "detaches" itself before making token request.

## v0.1.0 (2025-07-16)

  * Initial release.
