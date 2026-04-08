module Main exposing (main)

import Browser
import Html exposing (Html, button, div, h2, header, input, label, p, section, span, text)
import Html.Attributes as Attr
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Time


-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


-- MODEL


type OrderType
    = Market
    | Limit
    | Stop


type alias OrderForm =
    { symbol : String
    , quantity : String
    , price : String
    , orderType : OrderType
    }


type alias RiskSnapshot =
    { var95 : Float
    , sharpeRatio : Float
    , maxDrawdown : Float
    }


type alias Greeks =
    { iv : Float
    , delta : Float
    , gamma : Float
    }


type RemoteData e a
    = NotAsked
    | Loading
    | Failure e
    | Success a


type alias Model =
    { form : OrderForm
    , risk : RemoteData String RiskSnapshot
    , greeks : RemoteData String Greeks
    , submission : RemoteData String String
    , tick : Maybe Time.Posix
    }


defaultForm : OrderForm
defaultForm =
    { symbol = "AAPL"
    , quantity = "100"
    , price = "150.00"
    , orderType = Limit
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { form = defaultForm
      , risk = Loading
      , greeks = Loading
      , submission = NotAsked
      , tick = Nothing
      }
    , Cmd.batch
        [ fetchRisk
        , fetchGreeks defaultForm.symbol
        ]
    )


-- UPDATE


type Msg
    = SymbolChanged String
    | QuantityChanged String
    | PriceChanged String
    | OrderTypeSelected OrderType
    | SubmitOrder
    | GotRisk (Result Http.Error RiskSnapshot)
    | GotGreeks (Result Http.Error Greeks)
    | GotSubmitResponse (Result Http.Error String)
    | Tick Time.Posix


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SymbolChanged sym ->
            let
                form =
                    model.form
            in
            ( { model | form = { form | symbol = sym }, greeks = Loading }
            , fetchGreeks sym
            )

        QuantityChanged qty ->
            let
                form =
                    model.form
            in
            ( { model | form = { form | quantity = qty } }, Cmd.none )

        PriceChanged prc ->
            let
                form =
                    model.form
            in
            ( { model | form = { form | price = prc } }, Cmd.none )

        OrderTypeSelected ot ->
            let
                form =
                    model.form
            in
            ( { model | form = { form | orderType = ot } }, Cmd.none )

        SubmitOrder ->
            ( { model | submission = Loading }
            , submitOrder model.form
            )

        GotRisk (Ok snapshot) ->
            ( { model | risk = Success snapshot }, Cmd.none )

        GotRisk (Err err) ->
            ( { model | risk = Failure (httpErrorToString err) }, Cmd.none )

        GotGreeks (Ok data) ->
            ( { model | greeks = Success data }, Cmd.none )

        GotGreeks (Err err) ->
            ( { model | greeks = Failure (httpErrorToString err) }, Cmd.none )

        GotSubmitResponse (Ok status) ->
            ( { model | submission = Success status }, Cmd.none )

        GotSubmitResponse (Err err) ->
            ( { model | submission = Failure (httpErrorToString err) }, Cmd.none )

        Tick posix ->
            ( { model | tick = Just posix }, Cmd.none )


httpErrorToString : Http.Error -> String
httpErrorToString err =
    case err of
        Http.BadUrl url ->
            "bad url: " ++ url

        Http.Timeout ->
            "request timed out"

        Http.NetworkError ->
            "network error"

        Http.BadStatus code ->
            "status " ++ String.fromInt code

        Http.BadBody body ->
            "decode error: " ++ body


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 1000 Tick


-- HTTP


fetchRisk : Cmd Msg
fetchRisk =
    Http.get
        { url = "http://localhost:8081/api/risk"
        , expect = Http.expectJson GotRisk riskDecoder
        }


fetchGreeks : String -> Cmd Msg
fetchGreeks symbol =
    Http.get
        { url =
            "http://localhost:9001/api/fsharp/iv"
                ++ "?symbol="
                ++ symbol
                ++ "&strike=150&expiry=0.25&rate=0.05&underlying=148.5"
        , expect = Http.expectJson GotGreeks greeksDecoder
        }


submitOrder : OrderForm -> Cmd Msg
submitOrder form =
    Http.post
        { url = "http://localhost:8080/api/orders"
        , body = Http.jsonBody (encodeOrderForm form)
        , expect = Http.expectJson GotSubmitResponse (Decode.field "status" Decode.string)
        }


encodeOrderForm : OrderForm -> Encode.Value
encodeOrderForm form =
    Encode.object
        [ ( "symbol", Encode.string form.symbol )
        , ( "quantity", Encode.string form.quantity )
        , ( "price", Encode.string form.price )
        , ( "order_type", Encode.string (orderTypeToString form.orderType) )
        ]


orderTypeToString : OrderType -> String
orderTypeToString ot =
    case ot of
        Market ->
            "MARKET"

        Limit ->
            "LIMIT"

        Stop ->
            "STOP"


riskDecoder : Decoder RiskSnapshot
riskDecoder =
    Decode.map3 RiskSnapshot
        (Decode.field "var_95" Decode.float)
        (Decode.field "sharpe_ratio" Decode.float)
        (Decode.field "max_drawdown" Decode.float)


greeksDecoder : Decoder Greeks
greeksDecoder =
    Decode.map3 Greeks
        (Decode.field "iv" Decode.float)
        (Decode.field "delta" Decode.float)
        (Decode.field "gamma" Decode.float)


-- VIEW


view : Model -> Html Msg
view model =
    div [ Attr.class "terminal" ]
        [ viewHeader model.tick
        , div [ Attr.class "layout" ]
            [ div [ Attr.class "col" ]
                [ viewOrderForm model.form model.submission
                , viewRisk model.risk
                ]
            , div [ Attr.class "col" ]
                [ viewGreeks model.greeks model.form.symbol
                , viewParadigmNote
                ]
            ]
        ]


viewHeader : Maybe Time.Posix -> Html Msg
viewHeader maybeTick =
    header [ Attr.class "topbar" ]
        [ span [ Attr.class "topbar-title" ] [ text "POLYGLOT ORDER TERMINAL" ]
        , span [ Attr.class "topbar-tag" ] [ text "Elm 0.19.1  /  TEA  /  no runtime exceptions" ]
        , span [ Attr.class "topbar-clock" ]
            [ text (maybeTick |> Maybe.map formatUtcTime |> Maybe.withDefault "--:--:--  UTC") ]
        ]


formatUtcTime : Time.Posix -> String
formatUtcTime posix =
    let
        totalSeconds =
            Time.posixToMillis posix // 1000

        h =
            modBy 24 (totalSeconds // 3600)

        m =
            modBy 60 (totalSeconds // 60)

        s =
            modBy 60 totalSeconds
    in
    String.padLeft 2 '0' (String.fromInt h)
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt m)
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt s)
        ++ "  UTC"


viewOrderForm : OrderForm -> RemoteData String String -> Html Msg
viewOrderForm form submission =
    section [ Attr.class "card" ]
        [ h2 [ Attr.class "card-title" ] [ text "Order Entry" ]
        , div [ Attr.class "field" ]
            [ label [ Attr.class "field-label" ] [ text "Symbol" ]
            , input
                [ Attr.type_ "text"
                , Attr.class "field-input"
                , Attr.value form.symbol
                , Attr.placeholder "e.g. AAPL"
                , onInput SymbolChanged
                ]
                []
            ]
        , div [ Attr.class "field" ]
            [ label [ Attr.class "field-label" ] [ text "Quantity" ]
            , input
                [ Attr.type_ "number"
                , Attr.class "field-input"
                , Attr.value form.quantity
                , Attr.min "1"
                , Attr.step "1"
                , onInput QuantityChanged
                ]
                []
            ]
        , div [ Attr.class "field" ]
            [ label [ Attr.class "field-label" ] [ text "Limit Price" ]
            , input
                [ Attr.type_ "number"
                , Attr.class "field-input"
                , Attr.value form.price
                , Attr.min "0"
                , Attr.step "0.01"
                , Attr.disabled (form.orderType == Market)
                , onInput PriceChanged
                ]
                []
            ]
        , div [ Attr.class "field" ]
            [ label [ Attr.class "field-label" ] [ text "Order Type" ]
            , div [ Attr.class "order-type-group" ]
                [ viewOrderTypeBtn "LIMIT" (form.orderType == Limit) (OrderTypeSelected Limit)
                , viewOrderTypeBtn "MARKET" (form.orderType == Market) (OrderTypeSelected Market)
                , viewOrderTypeBtn "STOP" (form.orderType == Stop) (OrderTypeSelected Stop)
                ]
            ]
        , button
            [ Attr.class "submit-btn"
            , onClick SubmitOrder
            , Attr.disabled (submission == Loading)
            ]
            [ text
                (if submission == Loading then
                    "Routing..."

                 else
                    "Submit Order"
                )
            ]
        , viewSubmission submission
        ]


viewOrderTypeBtn : String -> Bool -> Msg -> Html Msg
viewOrderTypeBtn label isActive msg =
    button
        [ Attr.class
            (if isActive then
                "ot-btn ot-btn--active"

             else
                "ot-btn"
            )
        , onClick msg
        ]
        [ text label ]


viewSubmission : RemoteData String String -> Html Msg
viewSubmission state =
    case state of
        NotAsked ->
            text ""

        Loading ->
            div [ Attr.class "notice notice--pending" ] [ text "Routing order to go-hub..." ]

        Success status ->
            div [ Attr.class "notice notice--ok" ] [ text ("Accepted  /  status: " ++ status) ]

        Failure err ->
            div [ Attr.class "notice notice--err" ] [ text ("Rejected  /  " ++ err) ]


viewRisk : RemoteData String RiskSnapshot -> Html Msg
viewRisk state =
    section [ Attr.class "card" ]
        [ h2 [ Attr.class "card-title" ] [ text "Portfolio Risk" ]
        , p [ Attr.class "card-source" ] [ text "source: rust-pipeline :8081" ]
        , case state of
            NotAsked ->
                text ""

            Loading ->
                div [ Attr.class "loading" ] [ text "Fetching..." ]

            Success snapshot ->
                div [ Attr.class "metrics" ]
                    [ viewMetric "VaR 95%" (formatFixed 4 snapshot.var95)
                    , viewMetric "Sharpe Ratio" (formatFixed 3 snapshot.sharpeRatio)
                    , viewMetric "Max Drawdown" (formatPercent snapshot.maxDrawdown)
                    ]

            Failure err ->
                div [ Attr.class "notice notice--err" ] [ text err ]
        ]


viewGreeks : RemoteData String Greeks -> String -> Html Msg
viewGreeks state symbol =
    section [ Attr.class "card" ]
        [ h2 [ Attr.class "card-title" ] [ text ("Options Greeks  /  " ++ symbol) ]
        , p [ Attr.class "card-source" ] [ text "source: fsharp-pricer :9001  (Newton-Raphson)" ]
        , case state of
            NotAsked ->
                text ""

            Loading ->
                div [ Attr.class "loading" ] [ text "Fetching..." ]

            Success greeks ->
                div [ Attr.class "metrics" ]
                    [ viewMetric "Implied Vol" (formatPercent greeks.iv)
                    , viewMetric "Delta" (formatFixed 4 greeks.delta)
                    , viewMetric "Gamma" (formatFixed 6 greeks.gamma)
                    ]

            Failure err ->
                div [ Attr.class "notice notice--err" ] [ text err ]
        ]


viewParadigmNote : Html Msg
viewParadigmNote =
    section [ Attr.class "card card--note" ]
        [ h2 [ Attr.class "card-title" ] [ text "Paradigm Guarantees" ]
        , div [ Attr.class "guarantee-list" ]
            [ viewGuarantee "No runtime exceptions" "All branches are exhaustively checked at compile time. Partial functions do not exist."
            , viewGuarantee "Managed effects" "All HTTP calls and subscriptions are declared as Cmd Msg. The view is a pure function of Model."
            , viewGuarantee "Unidirectional flow" "Msg -> update -> Model -> view. State mutation is impossible outside of update."
            , viewGuarantee "Immutable state" "Model is replaced on every update cycle. In-place mutation is not part of the language."
            ]
        ]


viewGuarantee : String -> String -> Html Msg
viewGuarantee title_ body_ =
    div [ Attr.class "guarantee" ]
        [ span [ Attr.class "guarantee-title" ] [ text title_ ]
        , span [ Attr.class "guarantee-body" ] [ text body_ ]
        ]


viewMetric : String -> String -> Html Msg
viewMetric label_ value_ =
    div [ Attr.class "metric" ]
        [ span [ Attr.class "metric-label" ] [ text label_ ]
        , span [ Attr.class "metric-value" ] [ text value_ ]
        ]


formatFixed : Int -> Float -> String
formatFixed decimals f =
    let
        factor =
            toFloat (10 ^ decimals)

        rounded =
            toFloat (round (f * factor)) / factor

        str =
            String.fromFloat rounded

        parts =
            String.split "." str

        intPart =
            Maybe.withDefault "0" (List.head parts)

        rawDec =
            Maybe.withDefault "" (List.head (List.drop 1 parts))

        paddedDec =
            String.left decimals (rawDec ++ String.repeat decimals "0")
    in
    intPart ++ "." ++ paddedDec


formatPercent : Float -> String
formatPercent f =
    formatFixed 2 (f * 100) ++ "%"
