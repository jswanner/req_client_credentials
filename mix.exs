defmodule ReqClientCredentials.MixProject do
  use Mix.Project

  @source_url "https://github.com/jswanner/req_client_credentials"
  @version "0.1.3"

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :docs, runtime: false, warn_if_outdated: true},
      {:plug, "~> 1.18", only: :test},
      {:req, "~> 0.5.0"}
    ]
  end

  def project do
    [
      app: :req_client_credentials,
      deps: deps(),
      docs: [
        source_url: @source_url,
        source_ref: "v#{@version}",
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"]
      ],
      elixir: "~> 1.14",
      package: [
        description: "Req plugin for OAuth 2.0 client credentials flow authentication",
        licenses: ["MIT"],
        links: %{
          "GitHub" => @source_url
        }
      ],
      preferred_cli_env: [
        docs: :docs,
        "hex.publish": :docs
      ],
      source_url: @source_url,
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end
end
