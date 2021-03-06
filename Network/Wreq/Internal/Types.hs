{-# LANGUAGE DeriveDataTypeable, FlexibleInstances, GADTs, RecordWildCards #-}

-- |
-- Module      : Network.Wreq.Internal.Types
-- Copyright   : (c) 2014 Bryan O'Sullivan
--
-- License     : BSD-style
-- Maintainer  : bos@serpentine.com
-- Stability   : experimental
-- Portability : GHC
--
-- HTTP client types.

module Network.Wreq.Internal.Types
    (
    -- * Client configuration
      Options(..)
    , Auth(..)
    -- * Request payloads
    , Payload(..)
    , Postable(..)
    , Putable(..)
    -- ** URL-encoded forms
    , FormParam(..)
    , FormValue(..)
    -- * Headers
    , ContentType
    , Link(..)
    -- * Errors
    , JSONError(..)
    ) where

import Control.Exception (Exception)
import Data.Text (Text)
import Data.Typeable (Typeable)
import Network.HTTP.Client (CookieJar, Manager, ManagerSettings, Request,
                            RequestBody, destroyCookieJar)
import Network.HTTP.Client.Internal (Proxy)
import Network.HTTP.Types (Header)
import Prelude hiding (head)
import qualified Data.ByteString as S

-- | A MIME content type, e.g. @\"application/octet-stream\"@.
type ContentType = S.ByteString

-- | Options for configuring a client.
data Options = Options {
    manager :: Either ManagerSettings Manager
  -- ^ Either configuration for a 'Manager', or an actual 'Manager'.
  --
  -- If only 'ManagerSettings' are provided, then by default a new
  -- 'Manager' will be created for each request.
  --
  -- /Note/: when issuing HTTP requests using 'Options'-based
  -- functions from the the "Network.Wreq.Session" module
  -- ('Network.Wreq.Session.getWith', 'Network.Wreq.Session.putWith',
  -- etc.), this field will be ignored.
  --
  -- An example of using a specific manager:
  --
  -- @
  --import "Network.HTTP.Client" ('Network.HTTP.Client.withManager')
  --
  --'Network.HTTP.Client.withManager' $ \\mgr -> do
  --  let opts = 'Network.Wreq.defaults' { 'manager' = Right mgr }
  --  'Network.Wreq.getWith' opts \"http:\/\/httpbin.org\/get\"
  -- @
  --
  -- An example of changing settings (this will use a separate
  -- 'Manager' for every request, so make sense only if you're issuing
  -- a tiny handful of requets):
  --
  -- @
  --import "Network.HTTP.Client" ('Network.HTTP.Client.defaultManagerSettings')
  --
  --let settings = 'Network.HTTP.Client.defaultManagerSettings' { managerConnCount = 5 }
  --    opts = 'Network.Wreq.defaults' { 'manager' = Left settings }
  --'Network.Wreq.getWith' opts \"http:\/\/httpbin.org\/get\"
  -- @
  , proxy :: Maybe Proxy
  -- ^ Host name and port for a proxy to use, if any.
  , auth :: Maybe Auth
  -- ^ Authentication information.
  --
  -- Example (note the use of TLS):
  --
  -- @
  --let opts = 'Network.Wreq.defaults' { 'auth' = 'Network.Wreq.basicAuth' \"user\" \"pass\" }
  --'Network.Wreq.getWith' opts \"https:\/\/httpbin.org\/basic-auth\/user\/pass\"
  -- @
  , headers :: [Header]
  -- ^ Additional headers to send with each request.
  --
  -- @
  --let opts = 'Network.Wreq.defaults' { 'headers' = [(\"Accept\", \"*\/*\")] }
  --'Network.Wreq.getWith' opts \"http:\/\/httpbin.org\/get\"
  -- @
  , params :: [(Text, Text)]
  -- ^ Key-value pairs to assemble into a query string to add to the
  -- end of a URL.
  --
  -- For example, given:
  --
  -- @
  --let opts = 'Network.Wreq.defaults' { params = [(\"sort\", \"ascending\"), (\"key\", \"name\")] }
  --'Network.Wreq.getWith' opts \"http:\/\/httpbin.org\/get\"
  -- @
  --
  -- This will generate a URL of the form:
  --
  -- >http://httpbin.org/get?sort=ascending&key=name
  , redirects :: Int
  -- ^ The maximum number of HTTP redirects to follow before giving up
  -- and throwing an exception.
  --
  -- In this example, a 'Network.HTTP.Client.HttpException' will be
  -- thrown with a 'Network.HTTP.Client.TooManyRedirects' constructor,
  -- because the maximum number of redirects allowed will be exceeded:
  --
  -- @
  --let opts = 'Network.Wreq.defaults' { 'redirects' = 3 }
  --'Network.Wreq.getWith' opts \"http:\/\/httpbin.org\/redirect/5\"
  -- @
  , cookies :: CookieJar
  -- ^ Cookies to set when issuing requests.
  --
  -- /Note/: when issuing HTTP requests using 'Options'-based
  -- functions from the the "Network.Wreq.Session" module
  -- ('Network.Wreq.Session.getWith', 'Network.Wreq.Session.putWith',
  -- etc.), this field will be used only for the /first/ HTTP request
  -- to be issued during a 'Network.Wreq.Session.Session'. Any changes
  -- changes made for subsequent requests will be ignored.
  } deriving (Typeable)

-- | Supported authentication types.
--
-- Do not use HTTP authentication unless you are using TLS encryption.
-- These authentication tokens can easily be captured and reused by an
-- attacker if transmitted in the clear.
data Auth = BasicAuth S.ByteString S.ByteString
            -- ^ Basic authentication. This consists of a plain
            -- username and password.
          | OAuth2Bearer S.ByteString
            -- ^ An OAuth2 bearer token. This is treated by many
            -- services as the equivalent of a username and password.
          | OAuth2Token S.ByteString
            -- ^ A not-quite-standard OAuth2 bearer token (that seems
            -- to be used only by GitHub). This is treated by whoever
            -- accepts it as the equivalent of a username and
            -- password.
          deriving (Eq, Show, Typeable)

instance Show Options where
  show (Options{..}) = concat ["Options { "
                              , "manager = ", case manager of
                                                Left _  -> "Left _"
                                                Right _ -> "Right _"
                              , ", proxy = ", show proxy
                              , ", auth = ", show auth
                              , ", headers = ", show headers
                              , ", params = ", show params
                              , ", redirects = ", show redirects
                              , ", cookies = ", show (destroyCookieJar cookies)
                              , " }"
                              ]

-- | A type that can be converted into a POST request payload.
class Postable a where
    postPayload :: a -> Request -> IO Request
    -- ^ Represent a value in the request body (and perhaps the
    -- headers) of a POST request.

-- | A type that can be converted into a PUT request payload.
class Putable a where
    putPayload :: a -> Request -> IO Request
    -- ^ Represent a value in the request body (and perhaps the
    -- headers) of a PUT request.

-- | A product type for representing more complex payload types.
data Payload where
    Raw  :: ContentType -> RequestBody -> Payload
  deriving (Typeable)

-- | A type that can be rendered as the value portion of a key\/value
-- pair for use in an @application\/x-www-form-urlencoded@ POST
-- body. Intended for use with the 'FormParam' type.
--
-- The instances for 'String', strict 'Data.Text.Text', and lazy
-- 'Data.Text.Lazy.Text' are all encoded using UTF-8 before being
-- URL-encoded.
--
-- The instance for 'Maybe' gives an empty string on 'Nothing',
-- and otherwise uses the contained type's instance.
class FormValue a where
    renderFormValue :: a -> S.ByteString
    -- ^ Render the given value.

-- | A key\/value pair for an @application\/x-www-form-urlencoded@
-- POST request body.
data FormParam where
    (:=) :: (FormValue v) => S.ByteString -> v -> FormParam

instance Show FormParam where
    show (a := b) = show a ++ " := " ++ show (renderFormValue b)

infixr 3 :=

-- | The error type used by 'Network.Wreq.asJSON' and
-- 'Network.Wreq.asValue' if a failure occurs when parsing a response
-- body as JSON.
data JSONError = JSONError String
               deriving (Show, Typeable)

instance Exception JSONError

-- | An element of a @Link@ header.
data Link = Link {
      linkURL :: S.ByteString
    , linkParams :: [(S.ByteString, S.ByteString)]
    } deriving (Eq, Show, Typeable)
