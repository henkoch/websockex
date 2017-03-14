defmodule WebSockex.ClientTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use WebSockex.Client

    def start_link(url, state) do
      WebSockex.Client.start_link(url, __MODULE__, state)
    end

    def catch_terminate(client, receiver) do
      WebSockex.Client.cast(client, {:set_attr, :catch_terminate, receiver})
    end

    def handle_cast({:pid_reply, pid}, state) do
      send(pid, :cast)
      {:ok, state}
    end
    def handle_cast({:set_state, state}, _state), do: {:ok, state}
    def handle_cast(:error, _), do: raise "an error"
    def handle_cast({:set_attr, key, attr}, state), do: {:ok, Map.put(state, key, attr)}
    def handle_cast({:get_state, pid}, state) do
      send(pid, state)
      {:ok, state}
    end
    def handle_cast({:send, frame}, state), do: {:reply, frame, state}
    def handle_cast(:close, state), do: {:close, state}
    def handle_cast({:close, code, reason}, state), do: {:close, {code, reason}, state}

    def handle_info({:send, frame}, state), do: {:reply, frame, state}
    def handle_info(:close, state), do: {:close, state}
    def handle_info({:close, code, reason}, state), do: {:close, {code, reason}, state}
    def handle_info({:pid_reply, pid}, state) do
      send(pid, :info)
      {:ok, state}
    end
    def handle_info(:bad_reply, _) do
      :lemon_pie
    end

    def terminate(_, %{catch_terminate: pid}), do: send(pid, :terminate)
    def terminate(_, _), do: :ok
  end

  setup do
    {:ok, {server_ref, url}} = WebSockex.TestServer.start(self())

    on_exit fn -> WebSockex.TestServer.shutdown(server_ref) end

    {:ok, pid} = TestClient.start_link(url, %{})
    server_pid = WebSockex.TestServer.receive_socket_pid

    [pid: pid, url: url, server_pid: server_pid]
  end

  test "handle changes state", context do
    rand_number = :rand.uniform(1000)

    WebSockex.Client.cast(context.pid, {:get_state, self()})
    refute_receive ^rand_number

    WebSockex.Client.cast(context.pid, {:set_state, rand_number})
    WebSockex.Client.cast(context.pid, {:get_state, self()})
    assert_receive ^rand_number
  end

  describe "handle_cast callback" do
    test "is called", context do
      WebSockex.Client.cast(context.pid, {:pid_reply, self()})

      assert_receive :cast
    end

    test "can reply with a message", context do
      message = :erlang.term_to_binary(:cast_msg)
      WebSockex.Client.cast(context.pid, {:send, {:binary, message}})

      assert_receive :cast_msg
    end

    test "can close the connection", context do
      WebSockex.Client.cast(context.pid, :close)

      assert_receive :normal_remote_closed
    end

    test "can close the connection with a code and a message", context do
      Process.flag(:trap_exit, true)
      WebSockex.Client.cast(context.pid, {:close, 4012, "Test Close"})

      assert_receive {:EXIT, _, {:local, 4012, "Test Close"}}
      assert_receive {4012, "Test Close"}
    end
  end

  describe "handle_info callback" do
    test "is called", context do
      send(context.pid, {:pid_reply, self()})

      assert_receive :info
    end

    test "can reply with a message", context do
      message = :erlang.term_to_binary(:info_msg)
      send(context.pid, {:send, {:binary, message}})

      assert_receive :info_msg
    end

    test "can close the connection normally", context do
      send(context.pid, :close)

      assert_receive :normal_remote_closed
    end

    test "can close the connection with a code and a message", context do
      Process.flag(:trap_exit, true)
      send(context.pid, {:close, 4012, "Test Close"})

      assert_receive {:EXIT, _, {:local, 4012, "Test Close"}}
      assert_receive {4012, "Test Close"}
    end
  end

  describe "terminate callback" do
    setup context do
      TestClient.catch_terminate(context.pid, self())
    end

    test "executes in a handle_info error", context do
      Process.unlink(context.pid)
      send(context.pid, :bad_reply)

      assert_receive :terminate
    end

    test "executes in handle_cast error", context do
      Process.unlink(context.pid)
      WebSockex.Client.cast(context.pid, :error)

      assert_receive :terminate
    end
  end

  test "can handle a ping frame", context do
    send(context.server_pid, :send_ping)

    assert_receive :received_pong
  end

  test "can handle a ping frame with a payload", context do
    send(context.server_pid, :send_payload_ping)

    assert_receive :received_payload_pong
  end

  test "Displays an informative error with a bad url" do
    assert TestClient.start_link("lemon_pie", :ok) == {:error, %WebSockex.URLError{url: "lemon_pie"}}
  end

  test "Raises a BadResponseError when a non valid callback response is given", context do
    Process.flag(:trap_exit, true)
    send(context.pid, :bad_reply)
    assert_receive {:EXIT, _, {%WebSockex.BadResponseError{}, _}}
  end
end
