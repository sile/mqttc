%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
%% @private
-module(mqttc_message_handler).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([new/0]).
-export([handle_send_message/2]).
-export([handle_recv_message/2]).

-export_type([state/0]).
-export_type([userdata/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% Macros & Records & Types
%%------------------------------------------------------------------------------------------------------------------------
-define(STATE, ?MODULE).

-record(?STATE,
        {
          next_message_id = 0 :: mqttm:message_id(),
          id_to_message = splay_tree:new() :: splay_tree:tree(mqttm:message_id(), {mqttm:message(), userdata()})
        }).

-opaque state() :: #?STATE{}.
-type userdata() :: term().

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
-spec new() -> state().
new() ->
    #?STATE{}.

-spec handle_send_message(mqttm:message(), state()) -> {ok, mqttm:message(), state()} | {error, Reason::term()}.
handle_send_message(Message, State) ->
    {ok, Message, State}.

-spec handle_recv_message(mqttm:message(), state()) -> {ok, mqttm:message(), state()} | {error, Reason::term()}.
handle_recv_message(Message, State) ->
    {ok, Message, State}.

