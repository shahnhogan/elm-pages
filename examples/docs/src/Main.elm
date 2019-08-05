port module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Element exposing (Element)
import Element.Border
import Element.Font as Font
import Html exposing (Html)
import Json.Encode
import List.Extra
import Mark
import Mark.Error
import MarkParser
import Markdown
import Metadata exposing (Metadata)
import OpenGraph
import Pages
import Pages.Content as Content exposing (Content)
import Pages.Head as Head
import Pages.Parser exposing (PageOrPost)
import RawContent
import SocialMeta
import Url exposing (Url)
import Yaml.Decode


port toJsPort : Json.Encode.Value -> Cmd msg


type alias Flags =
    {}


main : Pages.Program Flags Model Msg (Metadata Msg) (Element Msg)
main =
    Pages.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , parser = MarkParser.document
        , frontmatterParser = frontmatterParser
        , content = RawContent.content
        , markdownToHtml = markdownToHtml
        , toJsPort = toJsPort
        , head = head
        }


markdownToHtml : String -> Element msg
markdownToHtml body =
    Markdown.toHtmlWith
        { githubFlavored = Just { tables = True, breaks = False }
        , defaultHighlighting = Nothing
        , sanitize = True
        , smartypants = False
        }
        []
        body
        |> Element.html


frontmatterParser : Yaml.Decode.Decoder (Metadata.Metadata msg)
frontmatterParser =
    Yaml.Decode.field "title" Yaml.Decode.string
        |> Yaml.Decode.map Metadata.PageMetadata
        |> Yaml.Decode.map Metadata.Page


type alias Model =
    {}


init : Pages.Flags Flags -> ( Model, Cmd Msg )
init flags =
    ( Model, Cmd.none )


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> PageOrPost (Metadata Msg) (Element Msg) -> { title : String, body : Html Msg }
view model pageOrPost =
    let
        { title, body } =
            pageOrPostView model pageOrPost
    in
    { title = title
    , body =
        body
            |> Element.layout
                [ Element.width Element.fill
                , Font.size 18
                , Font.family [ Font.typeface "Roboto" ]
                , Font.color (Element.rgba255 0 0 0 0.8)
                ]
    }


pageOrPostView : Model -> PageOrPost (Metadata Msg) (Element Msg) -> { title : String, body : Element Msg }
pageOrPostView model pageOrPost =
    case pageOrPost.metadata of
        Metadata.Page metadata ->
            { title = metadata.title
            , body =
                [ header
                , Element.column
                    [ Element.padding 50
                    , Element.spacing 60
                    ]
                    pageOrPost.view
                ]
                    |> Element.textColumn
                        [ Element.width Element.fill
                        ]
            }

        Metadata.Article metadata ->
            { title = metadata.title.raw
            , body =
                (header :: pageOrPost.view)
                    |> Element.textColumn
                        [ Element.width Element.fill
                        , Element.spacing 80
                        ]
            }


header : Element msg
header =
    Element.row [ Element.padding 20, Element.spaceEvenly ]
        [ Element.el [ Font.size 30 ]
            (Element.link [] { url = "/", label = Element.text "elm-pages" })
        , Element.row [ Element.spacing 15 ]
            [ Element.link [] { url = "/docs", label = Element.text "Docs" }
            , Element.link [] { url = "/blog", label = Element.text "Blog" }
            ]
        ]


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/abouts-cards>
<https://htmlhead.dev>
<https://html.spec.whatwg.org/multipage/semantics.html#standard-metadata-names>
<https://ogp.me/>
-}
head : Metadata.Metadata msg -> List Head.Tag
head metadata =
    let
        themeColor =
            "#ffffff"
    in
    [ Head.metaName "theme-color" themeColor
    , Head.canonicalLink canonicalUrl
    ]
        ++ pageTags metadata


canonicalUrl =
    "https://elm-pages.com"


siteTagline =
    "A statically typed site generator - elm-pages"


pageTags metadata =
    case metadata of
        Metadata.Page record ->
            OpenGraph.website
                { url = canonicalUrl
                , name = "elm-pages"
                , image = { url = "", alt = "", dimensions = Nothing, secureUrl = Nothing }
                , description = Just siteTagline
                }

        Metadata.Article meta ->
            let
                description =
                    meta.description.raw

                title =
                    meta.title.raw

                image =
                    ""
            in
            [ Head.description description
            , Head.metaName "image" image
            ]
                ++ SocialMeta.summaryLarge
                    { title = meta.title.raw
                    , description = Just description
                    , siteUser = Nothing
                    , image = Just { url = image, alt = description }
                    }
