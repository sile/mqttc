%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
-module(mqttc_conn_tests).

-include_lib("eunit/include/eunit.hrl").
-include("mqttc_eunit.hrl").

-on_load(on_load/0).

%%------------------------------------------------------------------------------------------------------------------------
%% Unit Tests
%%------------------------------------------------------------------------------------------------------------------------
start_and_connect_test_() ->
    {foreach, spawn,
     fun () -> ok = meck:new(gen_tcp, [unstick]) end,
     fun (_) -> _ = meck:unload() end,
     [
      {"start and stop",
       fun () ->
               %% mock
               Socket = self(), % dummy socket
               ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
               ok = meck:expect(gen_tcp, controlling_process, 2, ok),
               ok = meck:expect(gen_tcp, send, 2, ok),
               ok = meck:expect(gen_tcp, recv, 3, {ok, iolist_to_binary(mqttm:encode(mqttm:make_connack(0)))}),
               ok = meck:expect(gen_tcp, close, 1, ok),

               %% start
               Arg = make_dummy_start_arg(),
               Result = mqttc_conn:start_link(Arg),
               ?assertMatch({ok, _}, Result),
               {ok, Pid} = Result,

               ?assertReceive({mqttc_conn, Pid, connected}),

               %% stop
               ok = mqttc_conn:stop(Pid),
               ?assertDown(Pid, normal),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_'])),
               ?assert(meck:called(gen_tcp, send, [Socket, '_'])),
               ?assert(meck:called(gen_tcp, recv, [Socket, '_', '_'])),
               ?assert(meck:called(gen_tcp, close, [Socket]))
       end},
      {"tcp connect failure: connect/4 returns error",
       fun () ->
               %% mock
               ok = meck:expect(gen_tcp, connect, 4, {error, something_wrong}),

               %% start: always be succeeded
               Arg = make_dummy_start_arg(),
               {ok, Pid} = mqttc_conn:start(Arg),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {tcp_error, connect, something_wrong}}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_']))
       end},
      {"tcp connect failure: connect/4 timeout",
       fun () ->
               %% mock
               ok = meck:expect(gen_tcp, connect, fun (_, _, _, _) -> timer:sleep(infinity) end), % blocking connect/4

               %% start: always be succeeded
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {tcp_error, connect, timeout}}),

               ?assert(not meck:called(gen_tcp, connect, ['_', '_', '_', '_'])) % gen_tcp:connect/4 was canceled
       end},
      {"tcp connect failure: abort",
       fun () ->
               %% mock
               ok = meck:expect(gen_tcp, connect, fun (_, _, _, _) -> meck:exception(error, something_wrong) end),

               %% start: always be succeeded
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {_Reason, _StackTrace}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_']))
       end},
      {"tcp send failure: send/2 returns error",
       fun () ->
               %% mock
               Socket = self(), % dummy socket
               ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
               ok = meck:expect(gen_tcp, controlling_process, 2, ok),
               ok = meck:expect(gen_tcp, send, 2, {error, something_wrong}),

               %% start
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {tcp_error, send, something_wrong}}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_'])),
               ?assert(meck:called(gen_tcp, send, [Socket, '_']))
       end},
      {"tcp send failure: send/2 timeout",
       fun () ->
               %% mock
               Socket = self(), % dummy socket
               ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
               ok = meck:expect(gen_tcp, controlling_process, 2, ok),
               ok = meck:expect(gen_tcp, send, fun (_, _) -> timer:sleep(infinity) end), % blocking

               %% start
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {tcp_error, send, timeout}}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_'])),
               ?assert(not meck:called(gen_tcp, send, [Socket, '_'])) % send/2 was canceled
       end},
      {"tcp recv failure: recv/3 returns error",
       fun () ->
               %% mock
               Socket = self(), % dummy socket
               ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
               ok = meck:expect(gen_tcp, controlling_process, 2, ok),
               ok = meck:expect(gen_tcp, send, 2, ok),
               ok = meck:expect(gen_tcp, recv, 3, {error, something_wrong}),

               %% start
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {tcp_error, recv, something_wrong}}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_'])),
               ?assert(meck:called(gen_tcp, send, [Socket, '_'])),
               ?assert(meck:called(gen_tcp, recv, [Socket, '_', '_']))
       end},
      {"tcp recv failure: recv3/ timeout",
       fun () ->
               %% mock
               Socket = self(), % dummy socket
               ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
               ok = meck:expect(gen_tcp, controlling_process, 2, ok),
               ok = meck:expect(gen_tcp, send, 2, ok),
               ok = meck:expect(gen_tcp, recv, fun (_, _, _) -> timer:sleep(infinity) end), % blocking

               %% start
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {tcp_error, recv, timeout}}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_'])),
               ?assert(meck:called(gen_tcp, send, [Socket, '_'])),
               ?assert(not meck:called(gen_tcp, recv, [Socket, '_', '_'])) % recv/3 was canceled
       end},
      {"mqtt connect failure: connect request rejected",
       fun () ->
               %% mock
               ErrorCode = 2,
               ErrorConnackMsg = mqttm:make_connack(ErrorCode),
               Socket = self(), % dummy socket
               ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
               ok = meck:expect(gen_tcp, controlling_process, 2, ok),
               ok = meck:expect(gen_tcp, send, 2, ok),
               ok = meck:expect(gen_tcp, recv, 3, {ok, iolist_to_binary(mqttm:encode(ErrorConnackMsg))}),

               %% start
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {mqtt_error, connect, {rejected, ErrorCode}}}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_'])),
               ?assert(meck:called(gen_tcp, send, [Socket, '_'])),
               ?assert(meck:called(gen_tcp, recv, [Socket, '_', '_']))
       end},
      {"mqtt connect failure: unexpected response message",
       fun () ->
               %% mock
               UnexpectedMsg = mqttm:make_disconnect(),
               Socket = self(), % dummy socket
               ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
               ok = meck:expect(gen_tcp, controlling_process, 2, ok),
               ok = meck:expect(gen_tcp, send, 2, ok),
               ok = meck:expect(gen_tcp, recv, 3, {ok, iolist_to_binary(mqttm:encode(UnexpectedMsg))}),

               %% start
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {mqtt_error, connect,
                                            {unexpected_response, [_, {messages, [UnexpectedMsg]}]}}}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_'])),
               ?assert(meck:called(gen_tcp, send, [Socket, '_'])),
               ?assert(meck:called(gen_tcp, recv, [Socket, '_', '_']))
       end},
      {"mqtt connect failure: wrong response bytes",
       fun () ->
               %% mock
               InvalidMqttBytes = <<0,0,0,0>>,
               Socket = self(), % dummy socket
               ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
               ok = meck:expect(gen_tcp, controlling_process, 2, ok),
               ok = meck:expect(gen_tcp, send, 2, ok),
               ok = meck:expect(gen_tcp, recv, 3, {ok, InvalidMqttBytes}),

               %% start
               {ok, Pid} = mqttc_conn:start(make_dummy_start_arg()),

               %% connection process exits with error reason
               ?assertDown(Pid, {{unknown_message_type, 0}, _StackTrace}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_'])),
               ?assert(meck:called(gen_tcp, send, [Socket, '_'])),
               ?assert(meck:called(gen_tcp, recv, [Socket, '_', '_']))
       end}
     ]}.

send_test_() ->
    {foreach, spawn,
     fun () ->
             ok = meck:new(gen_tcp, [unstick]),

             Socket = self(), % dummy socket
             ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
             ok = meck:expect(gen_tcp, controlling_process, 2, ok),
             ok = meck:expect(gen_tcp, send, 2, ok),
             ok = meck:expect(gen_tcp, recv, 3, {ok, iolist_to_binary(mqttm:encode(mqttm:make_connack(0)))}),
             ok = meck:expect(gen_tcp, close, 1, ok)
     end,
     fun (_) ->
             _ = meck:unload()
     end,
     [
      {"send MQTT message",
       fun () ->
               {ok, Conn} = mqttc_conn:start(make_dummy_start_arg()),

               Msg = mqttm:make_pingreq(),
               ?assert(not meck:called(gen_tcp, send, ['_', mqttm:encode(Msg)])),
               ?assertEqual(ok, mqttc_conn:send(Conn, Msg)),

               _ = sys:get_state(Conn), % for synchonization
               ?assert(meck:called(gen_tcp, send, ['_', mqttm:encode(Msg)]))
       end},
      {"connection process will exit if sending message is failed",
       fun () ->
               {ok, Conn} = mqttc_conn:start(make_dummy_start_arg()),

               ?executeThenAssertDown(
                  begin
                      ok = meck:expect(gen_tcp, send, 2, {error, something_wrong}),
                      Msg = mqttm:make_pingreq(),
                      ?assertEqual(ok, mqttc_conn:send(Conn, Msg)) % Return value of send/2 always be 'ok',
                  end,
                  Conn, {shutdown, {tcp_error, send, something_wrong}})
       end}
     ]}.

recv_test_() ->
    {foreach, spawn,
     fun () ->
             ok = meck:new(inet, [unstick]),
             ok = meck:new(gen_tcp, [unstick]),

             Socket = self(), % dummy socket
             ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
             ok = meck:expect(gen_tcp, controlling_process, 2, ok),
             ok = meck:expect(gen_tcp, send, 2, ok),
             ok = meck:expect(gen_tcp, recv, 3, {ok, iolist_to_binary(mqttm:encode(mqttm:make_connack(0)))}),
             ok = meck:expect(gen_tcp, close, 1, ok)
     end,
     fun (_) ->
             _ = meck:unload()
     end,
     [
      {"connection received message is redirected to owner process",
       fun () ->
               {ok, Conn} = mqttc_conn:start(make_dummy_start_arg(self())),

               ok = meck:expect(inet, setopts, 2, ok),
               ok = mqttc_conn:activate(Conn),

               Socket = mqttc_conn:get_socket(Conn),
               Msg = mqttm:make_pingresp(),
               Conn ! {tcp, Socket, iolist_to_binary(mqttm:encode(Msg))}, % emulate sending tcp data

               ?assertAlive(Conn),
               ?assertReceive({mqttc_conn, Conn, Msg}),

               ?assert(meck:called(inet, setopts, [Socket, [{active, true}]]))
       end},
      {"connection received message is redirected to owner process only when connection process is active",
       fun () ->
               {ok, Conn} = mqttc_conn:start(make_dummy_start_arg(self())),

               ok = meck:expect(inet, setopts, 2, ok),
               Socket = mqttc_conn:get_socket(Conn),
               Msg = mqttm:make_pingresp(),
               Conn ! {tcp, Socket, iolist_to_binary(mqttm:encode(Msg))}, % emulate sending tcp data

               %% inactive
               ?assertNotReceive({mqttc_conn, Conn, Msg}),

               %% active
               ok = mqttc_conn:activate(Conn),
               ?assertReceive({mqttc_conn, Conn, Msg}),

               %% inactive
               ok = mqttc_conn:inactivate(Conn),
               Conn ! {tcp, Socket, iolist_to_binary(mqttm:encode(Msg))}, % emulate sending tcp data
               ?assertNotReceive({mqttc_conn, Conn, Msg}),

               %% active
               ok = mqttc_conn:activate(Conn),
               ?assertReceive({mqttc_conn, Conn, Msg}),

               ?assertAlive(Conn)
       end},
      {"handling of fragmented TCP data",
       fun () ->
               {ok, Conn} = mqttc_conn:start(make_dummy_start_arg(self())),

               ok = meck:expect(inet, setopts, 2, ok),
               ok = mqttc_conn:activate(Conn),

               Socket = mqttc_conn:get_socket(Conn),
               Msg = mqttm:make_pingresp(),
               lists:foreach(fun (B) -> Conn ! {tcp, Socket, <<B>>} end,
                             binary_to_list(iolist_to_binary(mqttm:encode(Msg)))),

               ?assertAlive(Conn),
               ?assertReceive({mqttc_conn, Conn, Msg})
       end}
     ]}.

signal_handling_test_() ->
    {foreach, spawn,
     fun () -> ok = meck:new(gen_tcp, [unstick]) end,
     fun (_) -> _ = meck:unload() end,
     [
      {"connection process exited when it receives a signal",
       with_connection(
         fun (Conn) ->
                 exit(Conn, {shutdown, hoge}),

                 ?assertDown(Conn, {shutdown, hoge})
         end)},
      {"'normal' signal is ignored",
       with_connection(
         fun (Conn) ->
                 exit(Conn, normal),

                 ?assertAlive(Conn)
         end)}
     ]}.

owner_down_test_() ->
    {foreach, spawn,
     fun () -> ok = meck:new(gen_tcp, [unstick]) end,
     fun (_) -> _ = meck:unload() end,
     [
      {"connection process will exit when it's owner is down",
       with_connection(
         spawn(timer, sleep, [infinity]),
         fun (Owner, Conn) ->
                 _ = sys:get_state(Conn), % for synchonization
                 exit(Owner, {shutdown, hoge}),

                 ?assertDown(Conn, {shutdown, {owner_down, Owner, {shutdown, hoge}}})
         end)},
      {"connection process will exit when it's owner is normally stopped",
       with_connection(
         spawn(fun () -> receive stop -> ok end end),
         fun (Owner, Conn) ->
                 _ = sys:get_state(Conn), % for synchonization

                 Owner ! stop,

                 ?assertDown(Conn, {shutdown, {owner_down, Owner, normal}})
         end)},
      {"non existing owner process",
       with_connection(
         spawn(fun () -> ok end), % immediately down
         fun (Owner, Conn) ->
                 ?assertDown(Conn, {shutdown, {owner_down, Owner, noproc}})
         end)}
     ]}.

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec on_load() -> ok.
on_load() ->
    _ = error_logger:tty(false),
    ok.

-spec make_dummy_start_arg() -> mqttc_conn:start_arg().
make_dummy_start_arg() ->
    make_dummy_start_arg(self()).

-spec make_dummy_start_arg(mqttc_conn:owner()) -> mqttc_conn:start_arg().
make_dummy_start_arg(Owner) ->
    ConncetArg = make_dummy_connect_arg(),
    {Owner, ConncetArg}.

-spec make_dummy_connect_arg() -> mqttc_conn:connect_arg().
make_dummy_connect_arg() ->
    ClientId = <<"hoge">>,
    Options =
        [
         {timeout, 50}
        ],
    {"localhost", 2020, ClientId, Options}.

-spec with_connection(fun ((mqttc_conn:connection()) -> any())) -> fun (() -> any()).
with_connection(Fun) ->
    fun () ->
            Socket = spawn_link(timer, sleep, [infinity]), % dummy socket
            ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
            ok = meck:expect(gen_tcp, controlling_process, 2, ok),
            ok = meck:expect(gen_tcp, send, 2, ok),
            ok = meck:expect(gen_tcp, recv, 3, {ok, iolist_to_binary(mqttm:encode(mqttm:make_connack(0)))}),
            ok = meck:expect(gen_tcp, close, 1, ok),
            
            %% start
            Result = mqttc_conn:start(make_dummy_start_arg()),
            ?assertMatch({ok, _}, Result),
            {ok, Pid} = Result,
            try
                Fun(Pid)
            after
                mqttc_conn:stop(Pid)
            end
    end.

-spec with_connection(mqttc_conn:owner(), fun ((mqttc_conn:owner(), mqttc_conn:connection()) -> any())) ->
                             fun (() -> any()).
with_connection(Owner, Fun) ->
    fun () ->
            Socket = spawn_link(timer, sleep, [infinity]), % dummy socket
            ok = meck:expect(gen_tcp, connect, 4, {ok, Socket}),
            ok = meck:expect(gen_tcp, controlling_process, 2, ok),
            ok = meck:expect(gen_tcp, send, 2, ok),
            ok = meck:expect(gen_tcp, recv, 3, {ok, iolist_to_binary(mqttm:encode(mqttm:make_connack(0)))}),
            ok = meck:expect(gen_tcp, close, 1, ok),
            
            %% start
            Result = mqttc_conn:start(make_dummy_start_arg(Owner)),
            ?assertMatch({ok, _}, Result),
            {ok, Pid} = Result,
            try
                Fun(Owner, Pid)
            after
                mqttc_conn:stop(Pid)
            end
    end.
