module Route.SmoothieId_.Edit exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Smoothies as Smoothies exposing (Smoothie)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation
import Form.Value
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    { smoothieId : String }


type alias NewItem =
    { name : String
    , description : String
    , price : Int
    , imageUrl : String
    }


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


pages : DataSource (List RouteParams)
pages =
    DataSource.succeed []


type alias Data =
    { smoothie : Smoothie
    }


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed ()
        |> MySession.expectSessionDataOrRedirect (Session.get "userId")
            (\userId () session ->
                ((Smoothies.find (Uuid routeParams.smoothieId)
                    |> Request.Hasura.dataSource
                 )
                    |> DataSource.map
                        (\maybeSmoothie ->
                            maybeSmoothie
                                |> Maybe.map (Data >> Response.render)
                                |> Maybe.withDefault (Response.errorPage ErrorPage.NotFound)
                        )
                )
                    |> DataSource.map (Tuple.pair session)
            )


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Request.formDataWithoutServerValidation [ form, deleteForm ]
        |> MySession.expectSessionDataOrRedirect (Session.get "userId" >> Maybe.map Uuid)
            (\userId parsed session ->
                case parsed of
                    Ok (Edit okParsed) ->
                        Smoothies.update (Uuid routeParams.smoothieId) okParsed
                            |> Request.Hasura.mutationDataSource
                            |> DataSource.map
                                (\_ ->
                                    ( session
                                    , Route.redirectTo Route.Index
                                    )
                                )

                    Ok Delete ->
                        Smoothies.delete (Uuid routeParams.smoothieId)
                            |> Request.Hasura.mutationDataSource
                            |> DataSource.map
                                (\_ ->
                                    ( session
                                    , Route.redirectTo Route.Index
                                    )
                                )

                    Err errors ->
                        let
                            _ =
                                Debug.log "@@@ERRORS" errors
                        in
                        DataSource.succeed
                            -- TODO need to render errors here
                            ( session, Response.render {} )
            )


head : StaticPayload Data ActionData RouteParams -> List Head.Tag
head static =
    []


type Action
    = Delete
    | Edit EditInfo


type alias EditInfo =
    { name : String, description : String, price : Int, imageUrl : String }


deleteForm : Form.HtmlForm String Action data Msg
deleteForm =
    Form.init
        { combine = Validation.succeed Delete
        , view =
            \formState ->
                [ Html.button
                    [ Attr.style "color" "red"
                    ]
                    [ Html.text "Delete" ]
                ]
        }
        |> Form.hiddenKind ( "kind", "delete" ) "Required"


form : Form.HtmlForm String Action Data Msg
form =
    Form.init
        (\name description price imageUrl ->
            { combine =
                Validation.succeed EditInfo
                    |> Validation.andMap name
                    |> Validation.andMap description
                    |> Validation.andMap price
                    |> Validation.andMap imageUrl
                    |> Validation.map Edit
            , view =
                \formState ->
                    let
                        errorsView field =
                            (if formState.submitAttempted || True then
                                formState.errors
                                    |> Form.errorsForField field
                                    |> List.map (\error -> Html.li [] [ Html.text error ])

                             else
                                []
                            )
                                |> Html.ul [ Attr.style "color" "red" ]

                        fieldView label field =
                            Html.div []
                                [ Html.label []
                                    [ Html.text (label ++ " ")
                                    , field |> Form.FieldView.input []
                                    ]
                                , errorsView field
                                ]
                    in
                    [ fieldView "Name" name
                    , fieldView "Description" description
                    , fieldView "Price" price
                    , fieldView "Image" imageUrl
                    , Html.button []
                        [ Html.text
                            (if formState.isTransitioning then
                                "Updating..."

                             else
                                "Update"
                            )
                        ]
                    ]
            }
        )
        |> Form.field "name"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\{ smoothie } -> Form.Value.string smoothie.name)
            )
        |> Form.field "description"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\{ smoothie } -> Form.Value.string smoothie.description)
            )
        |> Form.field "price"
            (Field.int { invalid = \_ -> "Invalid int" }
                |> Field.required "Required"
                |> Field.withMin (Form.Value.int 1) "Price must be at least $1"
                |> Field.withInitialValue (\{ smoothie } -> Form.Value.int smoothie.price)
            )
        |> Form.field "imageUrl"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\{ smoothie } -> Form.Value.string smoothie.unsplashImage)
            )
        |> Form.hiddenKind ( "kind", "edit" ) "Required"


type Media
    = Article
    | Book
    | Video


parseIgnoreErrors : ( Maybe parsed, Dict String (List error) ) -> Result (Dict String (List error)) parsed
parseIgnoreErrors ( maybeParsed, fieldErrors ) =
    case maybeParsed of
        Just parsed ->
            Ok parsed

        _ ->
            Err fieldErrors


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    let
        pendingCreation : Maybe NewItem
        pendingCreation =
            form
                |> Form.parse "form" app app.data
                |> parseIgnoreErrors
                |> Result.toMaybe
                |> Maybe.andThen
                    (\actionItem ->
                        case actionItem of
                            Edit newItem ->
                                Just newItem

                            _ ->
                                Nothing
                    )
    in
    { title = "Update Item"
    , body =
        [ Html.h2 [] [ Html.text "Update item" ]
        , form
            |> Form.toDynamicTransition "form"
            |> Form.renderHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                -- TODO
                Nothing
                app
                app.data
        , pendingCreation
            |> Maybe.map pendingView
            |> Maybe.withDefault (Html.div [] [])
        , deleteForm
            |> Form.toDynamicTransition "delete-form"
            |> Form.renderHtml []
                -- TODO
                Nothing
                app
                app.data
        ]
    }


pendingView : NewItem -> Html (Pages.Msg.Msg Msg)
pendingView item =
    Html.div [ Attr.class "item" ]
        [ Html.div []
            [ Html.h3 [] [ Html.text item.name ]
            , Html.p [] [ Html.text item.description ]
            , Html.p [] [ "$" ++ String.fromInt item.price |> Html.text ]
            ]
        , Html.div []
            [ Html.img
                [ Attr.src (item.imageUrl ++ "?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&auto=format&fit=crop&w=600&h=903") ]
                []
            ]
        ]
