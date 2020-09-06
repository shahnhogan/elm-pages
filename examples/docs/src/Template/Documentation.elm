module Template.Documentation exposing (Model, Msg, decoder, template)

import DocSidebar
import Element exposing (Element)
import Element.Events
import Element.Font as Font
import Element.Region
import Global
import GlobalMetadata
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import MarkdownRenderer
import Pages exposing (images)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Palette
import SiteConfig
import Template
import TemplateDocument exposing (TemplateDocument)
import TemplateMetadata exposing (Documentation)


type alias StaticData =
    ()


type alias Model =
    {}


type Msg
    = Increment


template : TemplateDocument Documentation StaticData Model Msg
template =
    Template.template
        { view = view
        , head = head
        , staticData = staticData
        , init = init
        , update = update
        }


init : Documentation -> ( Model, Cmd Msg )
init metadata =
    ( {}, Cmd.none )


update : Documentation -> Msg -> Model -> ( Model, Cmd Msg, Global.GlobalMsg )
update metadata msg model =
    case msg of
        Increment ->
            ( model, Cmd.none, Global.IncrementFromChild )


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    StaticHttp.succeed ()


decoder : Decode.Decoder Documentation
decoder =
    Decode.map Documentation
        (Decode.field "title" Decode.string)


head : StaticData -> PagePath.PagePath Pages.PathKey -> Documentation -> List (Head.Tag Pages.PathKey)
head static currentPath meta =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = SiteConfig.tagline
        , locale = Nothing
        , title = meta.title
        }
        |> Seo.website


view :
    Global.Model
    -> List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
    -> StaticData
    -> Model
    -> Documentation
    -> Global.RenderedBody
    -> { title : String, body : Element Msg }
view globalModel allMetadata static model metadata rendered =
    { title = metadata.title
    , body =
        [ Element.row []
            [ counterView globalModel
            , DocSidebar.view
                Pages.pages.index
                allMetadata
                |> Element.el [ Element.width (Element.fillPortion 2), Element.alignTop, Element.height Element.fill ]
            , Element.column [ Element.width (Element.fillPortion 8), Element.padding 35, Element.spacing 15 ]
                [ Palette.heading 1 [ Element.text metadata.title ]
                , Element.column [ Element.spacing 20 ]
                    [ tocView (Tuple.first rendered)
                    , Element.column
                        [ Element.padding 50
                        , Element.spacing 30
                        , Element.Region.mainContent
                        ]
                        (Tuple.second rendered |> List.map (Element.map never))
                    ]
                ]
            ]
        ]
            |> Element.textColumn
                [ Element.width Element.fill
                , Element.height Element.fill
                ]
    }


counterView : Global.Model -> Element Msg
counterView globalModel =
    Element.el [ Element.Events.onClick Increment ] (Element.text <| "Docs count: " ++ String.fromInt globalModel.counter)


tocView : MarkdownRenderer.TableOfContents -> Element msg
tocView toc =
    Element.column [ Element.alignTop, Element.spacing 20 ]
        [ Element.el [ Font.bold, Font.size 22 ] (Element.text "Table of Contents")
        , Element.column [ Element.spacing 10 ]
            (toc
                |> List.map
                    (\heading ->
                        Element.link [ Font.color (Element.rgb255 100 100 100) ]
                            { url = "#" ++ heading.anchorId
                            , label = Element.text heading.name
                            }
                    )
            )
        ]
