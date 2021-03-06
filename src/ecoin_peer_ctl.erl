%% @doc Controlling peer process
%%      This is processes initate new incoming
%%      and outgoing connection. It does the version
%%      handshake and validate that the connection
%%      should indeed be used. After the handshake is
%%      done it spawns a sending and a receiving process.
-module(ecoin_peer_ctl).

-behaviour(gen_server).

-export([send/2,
         start_link/1]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
          send_pid :: pid(),
          recv_pid :: pid(),
          socket   :: inet:socket()
         }).

-include("ecoin.hrl").

%% @doc Send an arbitrary message to a peer
-spec send(pid(), payload() | command_without_payload()) -> ok.
send(Peer, Message) ->
    gen_server:cast(Peer, {send, Message}).

%% @doc Start a new outgoing peer process
-spec start_link(#net_addr{}) -> {ok, pid()}.
start_link(Peer) ->
    proc_lib:start_link(?MODULE, init, [Peer]).

-spec init(#net_addr{}) -> {ok, #state{}}.
init(#net_addr{ip = IP, port = Port} = Peer) ->
    ok = proc_lib:init_ack({ok, self()}),

    %% Connect to peer
    Timeout = ecoin_config:connection_timeout(),
    {ok, Socket} = ranch_tcp:connect(IP, Port, [], Timeout),

    %% Create statistics this peer, we key it on the socket
    ecoin_stats:create(Socket),

    %% Do the handshake and keep the peers version
    Version = handshake(Socket, Peer),

    %% Inform the peer manager about the peers version and
    %% that the peer is connected
    ecoin_peer_man:connected(Version),

    %% Create the send and receive processes
    {ok, SendPid} = ecoin_peer_send:start_link(Socket),
    {ok, RecvPid} = ecoin_peer_recv:start_link(Socket, self(), SendPid),

    State = #state{send_pid = SendPid,
                   recv_pid = RecvPid,
                   socket   = Socket},

    %% Enter gen_server loop
    gen_server:enter_loop(?MODULE, [], State).

handle_call(_, _, State) ->
    {stop, not_used, State}.

handle_cast({send, Message}, #state{send_pid = SendPid} = State) ->
    ecoin_peer_send:send(SendPid, Message),
    {noreply, State}.

handle_info(_, State) ->
    {stop, not_used, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% @doc Initial handshake - outgoing
%%      - Send our version
%%      - Receive peer version
%%        * Check if connection to self
%%      - TODO: Validate peer version
%%      - Send and receive veracks
-spec handshake(socket(), #net_addr{}) -> #version{}.
handshake(Socket, Peer) ->
    %% Create and send our version
    MyVersion = ecoin_version:new(Peer),
    ok = ecoin_message:send(Socket, MyVersion),

    %% Receive the peers version
    #message{network = Network,
             command = version,
             payload = Version} = ecoin_message:recv(Socket),

    %% Assert that we do not connect to ourselves
    true = (MyVersion#version.nounce /= Version#version.nounce),

    %% Send and receive veracks
    ok = ecoin_message:send(Socket, verack),
    #message{network = Network,
             command = verack} = ecoin_message:recv(Socket),

    %% Return the peers version
    Version.
