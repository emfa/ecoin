-module(ecoin_getheaders).

-export([encode/1,
         decode/1]).

-include("ecoin.hrl").

%% @doc Encode a getheaders message
-spec encode(#getheaders{}) -> binary().
encode(#getheaders{
          version   = Version,
          locator   = Locator,
          hash_stop = HashStop
         }) ->
    ecoin_locator:encode(Version, Locator, HashStop).

%% @doc Decode a getheaders message
-spec decode(binary()) -> #getheaders{}.
decode(Binary) ->
    {Version, Locator, HashStop} = ecoin_locator:decode(Binary),
    #getheaders{
       version   = Version,
       locator   = Locator,
       hash_stop = HashStop
      }.
