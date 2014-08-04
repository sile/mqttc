%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
-module(mqttc_session_tests).

-include_lib("eunit/include/eunit.hrl").
-include("mqttc_eunit.hrl").

-on_load(on_load/0).

%%------------------------------------------------------------------------------------------------------------------------
%% Unit Tests
%%------------------------------------------------------------------------------------------------------------------------
start_and_connect_test_() ->
    {foreach, spawn,
     fun () -> ok end,
     fun (_) -> ok end,
     [
      {"start and stop",
       fun () ->
               %% start
               Result = mqttc_session:start_link(make_dummy_start_arg()),
               ?assertMatch({ok, _}, Result),
               {ok, Pid} = Result,

               %% stop
               ok = mqttc_conn:stop(Pid),
               ?assertDown(Pid, normal)
       end}
     ]}.

signal_handling_test_() ->
    {foreach, spawn,
     fun () -> ok end,
     fun (_) -> ok end,
     [
      {"session process exited when it receives a signal",
       fun () ->
               {ok, Pid} = mqttc_session:start(make_dummy_start_arg()),
               exit(Pid, {shutdown, hoge}),

               ?assertDown(Pid, {shutdown, hoge})
       end},
      {"'normal' signal is ignored",
       fun () ->
               {ok, Pid} = mqttc_session:start_link(make_dummy_start_arg()),
               exit(Pid, normal),

               ?assertAlive(Pid)
       end}
     ]}.

owner_down_test_() ->
    {foreach, spawn,
     fun () -> ok end,
     fun (_) -> ok end,
     [
      {"session process will exit when it's owner is down",
       fun () ->
               Owner = spawn(timer, sleep, [infinity]),
               {ok, Pid} = mqttc_session:start(make_dummy_start_arg(Owner)),

               exit(Owner, {shutdown, hoge}),

               ?assertDown(Pid, {shutdown, {owner_down, Owner, {shutdown, hoge}}})
       end},
      {"connection process will exit when it's owner is normally stopped",
       fun () ->
               Owner = spawn(fun () -> receive stop -> ok end end),
               {ok, Pid} = mqttc_session:start(make_dummy_start_arg(Owner)),

               ?executeThenAssertDown(
                  Owner ! stop,
                  Pid, {shutdown, {owner_down, Owner, normal}})
       end}
     ]}.

connect_test_() ->
    {foreach, spawn,
     fun () ->
             ok = meck:new(mqttc_conn_sup, []),
             ok = meck:new(mqttc_conn, [])
     end,
     fun (_) ->
             _ = meck:unload()
     end,
     [
      {"basic connect",
       fun () ->
               %% start
               {ok, Pid} = mqttc_session:start_link(make_dummy_start_arg()),
               ?assertEqual(disconnected, mqttc_session:get_status(Pid)),

               %% connect
               ok = mock_successful_connect(Pid),
               ?assertEqual(ok, mqttc_session:connect(Pid, "localhost", 1883, [])),
               ?assertEqual(connected, mqttc_session:get_status(Pid))
       end},
      {"connect => disconnect => connect",
       fun () ->
               %% start
               {ok, Pid} = mqttc_session:start_link(make_dummy_start_arg()),
               ?assertEqual(disconnected, mqttc_session:get_status(Pid)),

               %% connect
               ok = mock_successful_connect(Pid),
               ?assertEqual(ok, mqttc_session:connect(Pid, "localhost", 1883, [])),
               ?assertEqual(connected, mqttc_session:get_status(Pid)),

               %% disconnect
               ok = meck:expect(mqttc_conn, stop, fun (Conn) -> _ = Conn ! stop, ok end),
               ?assertEqual(ok, mqttc_session:disconnect(Pid, 1000)),
               ?assertEqual(disconnected, mqttc_session:get_status(Pid)),

               %% connect
               ?assertEqual(ok, mqttc_session:connect(Pid, "localhost", 1883, [])),
               ?assertEqual(connected, mqttc_session:get_status(Pid))
       end},
      {"invalid request: connect => connect",
       fun () ->
               %% start
               {ok, Pid} = mqttc_session:start_link(make_dummy_start_arg()),
               ?assertEqual(disconnected, mqttc_session:get_status(Pid)),

               %% connect
               ok = mock_successful_connect(Pid),
               ?assertEqual(ok, mqttc_session:connect(Pid, "localhost", 1883, [])),
               ?assertEqual(connected, mqttc_session:get_status(Pid)),

               %% connect
               ?assertEqual({error, {mqtt_error, connect, connected}}, mqttc_session:connect(Pid, "localhost", 1883, [])),
               ?assertEqual(connected, mqttc_session:get_status(Pid))
       end},
      {"disconnect request always return 'ok'",
       fun () ->
               %% start
               {ok, Pid} = mqttc_session:start_link(make_dummy_start_arg()),
               ?assertEqual(disconnected, mqttc_session:get_status(Pid)),

               %% disconnect
               ok = meck:expect(mqttc_conn, stop, fun (Conn) -> _ = Conn ! stop, ok end),
               ?assertEqual(ok, mqttc_session:disconnect(Pid, 1000)),
               ?assertEqual(disconnected, mqttc_session:get_status(Pid))
       end}
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
    ClientId = <<"hoge">>,
    {undefined, Owner, ClientId}.

-spec mock_successful_connect(mqttc_session:session()) -> ok.
mock_successful_connect(SessionPid) ->
    ok = meck:expect(mqttc_conn_sup, start_child,
                     fun (_) ->
                             {ok,
                              spawn_link(fun () ->
                                                 SessionPid ! {mqttc_conn, self(), connected},
                                                 receive
                                                     stop -> ok
                                                 end
                                         end)}
                     end),
    ok.
