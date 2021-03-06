-module(ecoin_addr).

-export([new/1,
         encode/1,
         decode/1,
         encode_net_addr/1,
         decode_net_addr/1,
         encode_ipaddress/1,
         decode_ipaddress/1]).

-include("ecoin.hrl").

%% @doc Create a new addr message in response to
%%      a getaddr message
-spec new(pid()) -> #addr{}.
new(ControlPid) ->
    ChoosePeers = fun([Pid, _, _]) when Pid == ControlPid ->
                          false;
                     ([_, #version{addr_from = AddrFrom}, Timestamp]) ->
                          {true, AddrFrom#net_addr{time = Timestamp}} end,
    ConnectedPeers = ets:match(?CONN_TAB, {'$0', connected, '$1', '$2'}),
    #addr{addr_list = lists:filtermap(ChoosePeers, ConnectedPeers)}.

%% @doc Encode an addr message
-spec encode(#addr{}) -> binary().
encode(#addr{addr_list = AddrList}) ->
    ecoin_protocol:encode_list(AddrList, fun encode_net_addr/1).

%% @doc Decode an addr message
-spec decode(binary()) -> #addr{}.
decode(Binary) ->
    AddrList = ecoin_protocol:decode_list(Binary, fun decode_net_addr/1),
    #addr{addr_list = AddrList}.

%% @doc Encode an net_addr structure
-spec encode_net_addr(#net_addr{}) -> iodata().
encode_net_addr(NetAddr) ->
  #net_addr{time     = Time,
            services = Services,
            ip       = IPAddr,
            port     = Port
           } = NetAddr,
     <<(ecoin_util:ts_to_int(Time)):32/little,
       (ecoin_version:encode_services(Services))/binary,
       (encode_ipaddress(IPAddr))/binary,
       Port:16>>.

%% @doc Decode an net_addr structure
-spec decode_net_addr(<<_:240, _:_*8>>) ->
    {#net_addr{}, binary()} | #net_addr{}.
decode_net_addr(<<Time:32/little,
                  Services:8/binary,
                  IPAddr:16/binary,
                  Port:16, Rest/binary>>) ->
    NetAddr = #net_addr{time     = ecoin_util:int_to_ts(Time),
                        services = ecoin_version:decode_services(Services),
                        ip       = decode_ipaddress(IPAddr),
                        port     = Port
                       },
    case byte_size(Rest) == 0 of
        true  -> NetAddr;
        false -> {NetAddr, Rest}
    end.

%% @doc Encode an IPv4/IPv6 address
-spec encode_ipaddress(ipaddr()) -> <<_:128>>.
encode_ipaddress({I0,I1,I2,I3}) ->
    <<16#FFFF:96, I0, I1, I2, I3>>;
encode_ipaddress({I0, I1, I2, I3, I4, I5, I6, I7}) ->
    <<I0:16, I1:16, I2:16, I3:16, I4:16, I5:16, I6:16, I7:16>>.

%% @doc Decode an IPv6 address
-spec decode_ipaddress(<<_:128>>) -> ipaddr().
decode_ipaddress(<<I0:16, I1:16, I2:16, I3:16, I4:16, I5:16, I6:16, I7:16>>) ->
    {I0, I1, I2, I3, I4, I5, I6, I7}.
