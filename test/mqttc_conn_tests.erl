%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
-module(mqttc_conn_tests).

-include_lib("eunit/include/eunit.hrl").
-include("mqttc_eunit.hrl").

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
               ok = meck:expect(gen_tcp, send, 2, ok),
               ok = meck:expect(gen_tcp, recv, 3, {ok, iolist_to_binary(mqttm:encode(mqttm:make_connack(0)))}),
               ok = meck:expect(gen_tcp, close, 1, ok),

               %% start
               Arg = make_dummy_start_arg(),
               Result = mqttc_conn:start_link(Arg),
               ?assertMatch({ok, _}, Result),
               {ok, Pid} = Result,

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
               process_flag(trap_exit, true),

               %% mock
               ok = meck:expect(gen_tcp, connect, 4, {error, something_wrong}),

               %% start: always be succeeded
               Arg = make_dummy_start_arg(),
               {ok, Pid} = mqttc_conn:start_link(Arg),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {tcp_error, connect, something_wrong}}),

               ?assert(meck:called(gen_tcp, connect, ['_', '_', '_', '_']))
       end},
      {"tcp connect failure: connect/4 timeout",
       fun () ->
               process_flag(trap_exit, true),

               %% mock
               ok = meck:expect(gen_tcp, connect, fun (_, _, _, _) -> timer:sleep(infinity) end), % blocking connect/4

               %% start: always be succeeded
               Arg = make_dummy_start_arg(),
               {ok, Pid} = mqttc_conn:start_link(Arg),

               %% connection process exits with error reason
               ?assertDown(Pid, {shutdown, {tcp_error, connect, timeout}}),

               ?assert(not meck:called(gen_tcp, connect, ['_', '_', '_', '_']))
       end}
     ]}.

%%------------------------------------------------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec make_dummy_start_arg() -> mqttc_conn:start_arg().
make_dummy_start_arg() ->
    Owner = self(),
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
