defmodule ReqClientCredentialsTest do
  use ExUnit.Case, async: true

  alias Plug.Conn

  doctest ReqClientCredentials

  setup context do
    test_origin = "https://test.host"
    token = Map.get(context, :token, "token_#{System.unique_integer()}")

    plug = fn
      %Conn{host: "bad-token.host"} = conn ->
        send(self(), {:token_request, conn})

        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"error" => "access_denied", "error_description" => "Unauthorized"})

      %Conn{host: "token.host"} = conn ->
        send(self(), {:token_request, conn})
        Req.Test.json(conn, %{access_token: token, token_type: "Bearer"})

      %Conn{} = conn ->
        case Conn.get_req_header(conn, "authorization") do
          ["Bearer unauthorized"] ->
            send(self(), {:unauthorized_request, conn})
            Conn.send_resp(conn, :unauthorized, "")

          _ ->
            send(self(), {:test_request, conn})
            Req.Test.text(conn, "ok")
        end
    end

    req =
      Req.new(
        url: test_origin <> "/path",
        client_credentials_params: [
          audience: test_origin,
          client_id: "client_id",
          client_secret: "client_secret"
        ],
        client_credentials_url: "https://token.host/oauth/token",
        plug: plug,
        plugins: [ReqClientCredentials]
      )

    ReqClientCredentials.bust_cache(req)

    {:ok, req: req, token: token}
  end

  describe "with audience param present" do
    test "requests token when audience matches request host", context do
      assert {:ok, _resp} = Req.get(context.req)
      assert_received {:token_request, _}
      assert_received {:test_request, conn}
      assert ["Bearer #{context.token}"] == Conn.get_req_header(conn, "authorization")
    end

    test "skips token request when audience does not match request host", context do
      assert {:ok, _resp} = Req.get(context.req, url: "https://other.host/path")
      refute_received {:token_request, _}
      assert_received {:test_request, conn}
      assert [] = Conn.get_req_header(conn, "authorization")
    end

    test "sends original request without authorization token if token request fails", context do
      assert {:ok, _resp} =
               Req.get(context.req, client_credentials_url: "https://bad-token.host/oauth/token")

      assert_receive {:token_request, _}
      assert_received {:test_request, conn}
      assert [] = Conn.get_req_header(conn, "authorization")
    end
  end

  describe "without client_credentials_url option" do
    test "skips token request", context do
      assert {:ok, _resp} =
               context.req
               |> Req.Request.delete_option(:client_credentials_url)
               |> Req.get()

      refute_received {:token_request, _}
      assert_received {:test_request, _}
    end
  end

  describe "caching" do
    test "uses cached token on cache hit", context do
      assert {:ok, _resp} = Req.get(context.req)
      assert_received {:token_request, _}
      assert_received {:test_request, _}

      assert {:ok, _resp} = Req.get(context.req)
      refute_received {:token_request, _}
      assert_received {:test_request, _}
    end

    test "request token on cache miss", context do
      req =
        Req.Request.merge_options(context.req,
          client_credentials_params: [client_id: "client_id", client_secret: "client_secret"]
        )

      assert {:ok, _resp} = Req.get(req)
      assert_received {:token_request, _}
      assert_received {:test_request, _}

      assert {:ok, _resp} = Req.get(req, url: "https://other.host/path")
      assert_received {:token_request, _}
      assert_received {:test_request, _}
    end

    @tag capture_log: true, token: "unauthorized"
    test "refreshes token once on unauthorized response", context do
      ReqClientCredentials.write_cache(context.req, {context.token, "Bearer"})

      assert {:ok, _resp} = Req.get(context.req)
      assert_received {:unauthorized_request, _}
      assert_received {:token_request, _}
      assert_received {:unauthorized_request, _}
      assert {:messages, []} = Process.info(self(), :messages)
    end
  end
end
