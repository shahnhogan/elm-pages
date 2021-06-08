module Pages.Internal.Platform.Effect exposing (Effect(..))

import DataSource.Http exposing (RequestDetails)
import Pages.Internal.Platform.ToJsPayload exposing (ToJsPayload, ToJsSuccessPayloadNewCombined)


type Effect
    = NoEffect
    | SendJsData ToJsPayload
    | FetchHttp { masked : RequestDetails, unmasked : RequestDetails }
    | ReadFile String
    | GetGlob String
    | Batch (List Effect)
    | SendSinglePage Bool ToJsSuccessPayloadNewCombined
    | Continue
