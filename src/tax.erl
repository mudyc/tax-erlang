-module(tax).
-compile(export_all).
%-export([calc_included/2,calc_excluded/2,rates/2]).

% total Price includes tax, i.e Price = Net + Tax
calc_included(Price, Rates) ->
        Taxes = maps:map(fun(Key,Tax)->
           case Tax of
              X when is_float(X) or is_integer(X) -> round(Price - Price/(1+X/100.0));
              _ -> Tax end
        end, Rates),
        maps:merge(#{ total => Price, withouttax => lists:foldl(fun(T,Acc)->case T of T when is_float(T) or is_integer(T) -> Acc-T; _ -> Acc end end, Price, maps:values(Taxes))}, Taxes).

% total is Price + tax 
calc_excluded(Price, Rates) ->
        Taxes = maps:map(fun(Key,Tax)->
           case Tax of X when is_float(X) or is_integer(X) -> round(Price*(X/100.0));
           _ -> Tax end
        end, Rates),
        maps:merge(#{ withouttax => Price, total => lists:foldl(fun(T,Acc)->case T of T when is_float(T) or is_integer(T) -> Acc+T; _ -> Acc end end, Price, maps:values(Taxes))}, Taxes).


rates(CountryCode, Zip) ->
       case CountryCode of
         % state + area
         "US" -> usa(Zip);


         % gst canada, australia
         "CA" -> canada(Zip);
         "AU" -> others("AU", gst);
         "IN" -> others("IN", gst);
         "HK" -> others("HK", gst);
         "MY" -> others("MY", gst);
         "NZ" -> others("NZ", gst);
         "SG" -> others("SG", gst);
         % other countries use vat
            _ -> case others(CountryCode, vat) of
                     null -> eu(CountryCode);
                        _ -> others(CountryCode, vat)
                 end
       end.

usa(Zip) ->
        Json = priv2json("zip2fips.json"),
        Fips = maps:get(list_to_binary(Zip), Json, <<"01">>), % fallback to alabama :p
        State = binary:part(Fips,0,2),
        Rates = priv2json("usa.json"),
        Rate = maps:get(State, Rates),
        Name = maps:get(<<"name">>,Rate),
        case maps:is_key(<<"bywire">>, Rate) of
            true -> #{ name => Name, tax => maps:get(<<"bywire">>,Rate) };
            _ -> case maps:is_key(<<"digi">>, Rate) of
                 true -> #{ name => Name, tax => maps:get(<<"digi">>,Rate) };
                 _ -> #{ name => Name, state_tax => maps:get(<<"state">>,Rate),
                         tax => (maps:get(<<"max">>, Rate) - maps:get(<<"state">>,Rate)) }
                 end
        end.

canada(Zip) ->
        Json = priv2json("canada.json"),
        Rate = maps:get(list_to_binary(string:substr(Zip, 1, 1)), Json, <<"A">>), % first is letter
        #{ name => maps:get(<<"name">>,Rate), gst => maps:get(<<"rate">>,Rate) }.

eu(Code) ->
        Json = priv2json("eu.json"),
        Datas = maps:get(<<"rates">>,Json),
        Country = lists:last(lists:filter(fun(Map)->maps:get(<<"country_code">>,Map) == list_to_binary(Code) end, Datas)),
        #{ vat => maps:get(<<"standard">>, maps:get(<<"rates">>, lists:last(maps:get(<<"periods">>, Country)))) }.

others(Code, Tax) ->
        Json = priv2json("others.json"),
        Rate = maps:get(list_to_binary(Code), Json, null),
        case Rate of
            null -> null;
               _ -> #{ Tax => maps:get(<<"rate">>,Rate) }
        end.

priv2json(FileName) ->
        File = code:priv_dir(tax) ++ "/" ++ FileName,
        {_, Content} = file:read_file(File),
        jsone:decode(Content, [{object_format, map}]).
