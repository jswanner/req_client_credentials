defmodule ReqClientCredentialsTest do
  use ExUnit.Case, async: true

  alias Plug.Conn

  doctest ReqClientCredentials

  @moduletag audience: "https://test.host",
             client_credentials_url: "https://token.host/oauth/token",
             response_status: :ok,
             token_response_status: :ok

  setup context do
    token = Map.get(context, :token, "token_#{System.unique_integer()}")

    plug = fn
      %Conn{host: "token.host"} = conn ->
        send(self(), {:token_request, conn})

        case context.token_response_status do
          :ok ->
            Req.Test.json(conn, %{access_token: token, token_type: "Bearer"})

          :unauthorized ->
            conn
            |> Plug.Conn.put_status(401)
            |> Req.Test.json(%{"error" => "access_denied", "error_description" => "Unauthorized"})
        end

      %Conn{} = conn ->
        case context.response_status do
          :ok ->
            send(self(), {:test_request, conn})
            Req.Test.text(conn, "ok")

          :unauthorized ->
            send(self(), {:unauthorized_request, conn})
            Conn.send_resp(conn, :unauthorized, "")
        end
    end

    req =
      Req.new(
        url: context.audience <> "/path",
        client_credentials: [
          form: [
            audience: context.audience,
            client_id: "client_id",
            client_secret: "client_secret"
          ],
          url: context.client_credentials_url
        ],
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

    @tag client_credentials_url: "https://other-token.host/oauth/token"
    test "skips token request when audience does not match request host", context do
      assert {:ok, _resp} = Req.get(context.req)
      refute_received {:token_request, _}
      assert_received {:test_request, conn}
      assert [] = Conn.get_req_header(conn, "authorization")
    end

    @tag client_credentials_url: "https://other-token.host/oauth/token",
         response_status: :unauthorized
    test "ignores unauthorized response for skipped token request", context do
      assert {:ok, resp} = Req.get(context.req, url: "https://other.host/path")
      refute_received {:token_request, _}
      assert_received {:unauthorized_request, conn}
      assert [] = Conn.get_req_header(conn, "authorization")
      assert 401 = resp.status
    end

    @tag token_response_status: :unauthorized
    test "skips original request if token request fails", context do
      assert {:ok, _resp} = Req.get(context.req)
      assert_receive {:token_request, _}
      refute_received {:test_request, _}
    end
  end

  describe "without client_credentials url option" do
    test "skips token request", context do
      assert {:ok, _resp} = Req.get(context.req, client_credentials: [])

      refute_received {:token_request, _}
      assert_received {:test_request, _}
    end
  end

  describe "using basic auth for token request" do
    test "sends configured userinfo", context do
      assert {:ok, _resp} =
               Req.get(context.req,
                 client_credentials: [
                   auth: {:basic, "user:pass"},
                   url: context.client_credentials_url
                 ]
               )

      assert_received {:token_request, conn}
      assert ["Basic #{Base.encode64("user:pass")}"] == Conn.get_req_header(conn, "authorization")
      assert_received {:test_request, conn}
      assert ["Bearer #{context.token}"] == Conn.get_req_header(conn, "authorization")
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
          client_credentials: [
            form: [client_id: "client_id", client_secret: "client_secret"],
            url: context.client_credentials_url
          ]
        )

      assert {:ok, _resp} = Req.get(req)
      assert_received {:token_request, _}
      assert_received {:test_request, _}

      assert {:ok, _resp} = Req.get(req, url: "https://other.host/path")
      assert_received {:token_request, _}
      assert_received {:test_request, _}

      assert {:ok, _resp} =
               Req.get(req,
                 client_credentials: [
                   form: [client_id: "other_id", client_secret: "client_secret"],
                   url: context.client_credentials_url
                 ]
               )

      assert_received {:token_request, _}
      assert_received {:test_request, _}
    end

    @tag capture_log: true, response_status: :unauthorized
    test "refreshes token once on unauthorized response", context do
      ReqClientCredentials.write_cache(context.req, context.token)

      assert {:ok, _resp} = Req.get(context.req)
      assert_received {:unauthorized_request, _}
      assert_received {:token_request, _}
      assert_received {:unauthorized_request, _}
      assert {:messages, []} = Process.info(self(), :messages)
    end
  end
end
