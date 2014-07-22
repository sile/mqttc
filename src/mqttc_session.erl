%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
-module(mqttc_session).

-behaviour(gen_fsm).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start_link/1]).
-export([stop/1]).
-export([get_status/1]).

-export_type([start_arg/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_fsm' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
%-export([disconnected/2, disconnected/3, connecting/2, connecting/3, connected/2, connected/3]).

%%------------------------------------------------------------------------------------------------------------------------
%% Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-record(state,
        {
          client_id :: mqttm:client_id()
        }).

-type start_arg() :: {mqttc:session_name_spec() | undefined, pid() | undefined, mqttm:client_id()}.

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec start_link(start_arg()) -> {ok, pid()} | {error, Reason} when
      Reason :: {already_started, pid()} | term().
start_link({undefined, LinkPid, ClientId}) ->
    gen_fsm:start_link(?MODULE, {LinkPid, ClientId}, []);
start_link({Name, LinkPid, ClientId}) ->
    gen_fsm:start_link(Name, ?MODULE, {LinkPid, ClientId}, []).

-spec stop(mqttc:session()) -> ok.
stop(Session) ->
    gen_fsm:send_all_state_event(Session, stop).

-spec get_status(mqttc:session()) -> mqttc:session_status().
get_status(Session) ->
    gen_fsm:sync_send_all_state_event(Session, get_status).

%%------------------------------------------------------------------------------------------------------------------------
%% 'gen_fsm' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init({LinkPid, ClientId}) when is_pid(LinkPid) ->
    true = link(LinkPid),
    init({undefined, ClientId});
init({undefined, ClientId}) ->
    State =
        #state{
           client_id = ClientId
          },
    {ok, disconnected, State}.

%% @private
handle_event(stop, _StateName, State) ->
    {stop, normal, State};
handle_event(Event, StateName, State) ->
    {stop, {unknown_event, Event, StateName}, State}.

%% @private
handle_sync_event(get_status, _From, StateName, State) ->
    {reply, StateName, StateName, State};
handle_sync_event(Event, From, StateName, State) ->
    {stop, {unknown_sync_event, Event, From, StateName}, State}.

%% @private
handle_info(Info, StateName, State) ->
    {stop, {unknown_info, Info, StateName}, State}.

%% @private
terminate(_Reason, _StateName, _State) ->
    ok.

%% @private
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.
