%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc supervisor for client MQTT session processes
%% @private
-module(mqttc_session_sup).

-behaviour(supervisor).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start_link/0, start_child/1]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'application' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1]).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @doc Starts supervisor process
-spec start_link() -> {ok, pid()} | {error, Reason::term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Starts child process
-spec start_child(mqttc_session:start_arg()) -> {ok, pid()} | {error, Reason::term()}.
start_child(Arg) ->
    supervisor:start_child(?MODULE, [Arg]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'application' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init([]) ->
    Session = mqttc_session,
    Children =
        [{Session, {Session, start_link, []}, temporary, 5000, worker, [Session]}],
    {ok, { {simple_one_for_one, 5, 10}, Children} }.
