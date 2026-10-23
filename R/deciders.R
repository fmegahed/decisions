#' The class of all deciders
#'
#' A decider names one model and says how to reach it. It holds no key: the
#' `credentials` function returns the key when `decide()` sends a request.
#'
#' @param provider The provider id: `"typesafe"`, `"openai"`, `"foundry"`,
#'   `"openrouter"` or `"systemone"`.
#' @param format The request format of `build_body()`: `"systemone"`,
#'   `"systemone_images"`, `"openai"` or `"openrouter"`.
#' @param base_url The server root. `decide()` appends the path of the
#'   provider.
#' @param model The model name (the deployment name for Foundry).
#' @param image_format `"assets"` or `"images"` for SystemOne servers, `NA`
#'   for OpenAI and OpenRouter.
#' @param input `"text"`, `"image"`, `"text+image"`, or `NA` when the input
#'   is not checked.
#' @param credentials A function with no arguments that returns the key, or
#'   `NULL` for no key.
#' @return A decider object.
#' @noRd
decider_class <- S7::new_class(
  "decider",
  properties = list(
    provider = S7::class_character,
    format = S7::class_character,
    base_url = S7::class_character,
    model = S7::class_character,
    image_format = S7::class_character,
    input = S7::class_character,
    credentials = S7::class_function
  )
)

#' Print a decider
#'
#' Shows the provider, the model, the URL, the request format and the input
#' type. It never calls or shows `credentials`, so no key appears.
#'
#' @param x A decider.
#' @param ... Not used.
#' @return `x`, invisibly.
#' @noRd
print_decider <- function(x, ...) {
  cat(
    paste0("<decider> ", provider_name(x)),
    paste0("* Model: ", x@model),
    paste0("* URL: ", decider_url(x)),
    paste0("* Request format: ", x@format),
    paste0("* Input: ", if (is.na(x@input)) "not checked" else x@input),
    sep = "\n"
  )
  invisible(x)
}

S7::method(print, decider_class) <- print_decider

#' Make a decider
#'
#' The shared constructor of the five `decider_*()` functions and of
#' `read_setup()`.
#'
#' @param provider,format,base_url,model,image_format The properties of the
#'   decider (see `decider_class`).
#' @param input `"text"`, `"image"`, `"text+image"`, or `NULL` to look the
#'   model up in the table of input types.
#' @param credentials A function that returns the key, or `NULL` to read the
#'   environment variable of the provider (see `provider_key()`) at request
#'   time.
#' @return A decider object.
#' @noRd
new_decider <- function(provider, format, base_url, model, input, credentials,
                        image_format = NA_character_) {
  if (!rlang::is_string(model) || !nzchar(model)) {
    cli::cli_abort("{.arg model} must be one non-empty string.")
  }
  if (!rlang::is_string(base_url) || !nzchar(base_url)) {
    cli::cli_abort("The server URL must be one non-empty string.")
  }
  if (!is.null(credentials) && !is.function(credentials)) {
    cli::cli_abort(
      "{.arg credentials} must be a function that returns the key, not the key."
    )
  }
  if (!is.null(input)) {
    input <- rlang::arg_match(input, c("text", "image", "text+image"))
  }
  decider_class(
    provider = provider,
    format = format,
    base_url = base_url,
    model = model,
    image_format = image_format,
    input = input %||% lookup_input(provider, model),
    credentials = credentials %||% env_credentials(provider_key(provider))
  )
}

#' Name the environment variable that holds the key of a provider
#'
#' @param provider The provider id of a decider.
#' @return `"TYPESAFE_API_KEY"`, `"OPENAI_API_KEY"`, `"AZURE_FOUNDRY_API_KEY"`
#'   or `"OPENROUTER_API_KEY"`; `NULL` for `"systemone"`, whose servers need
#'   no key by default. It stops with an error for an unknown provider.
#' @noRd
provider_key <- function(provider) {
  switch(provider,
    typesafe = "TYPESAFE_API_KEY",
    openai = "OPENAI_API_KEY",
    foundry = "AZURE_FOUNDRY_API_KEY",
    openrouter = "OPENROUTER_API_KEY",
    systemone = NULL,
    cli::cli_abort("Unknown provider {.val {provider}}.")
  )
}

#' Make a function that reads a key from the environment
#'
#' @param key The name of the environment variable, or `NULL`.
#' @return A function with no arguments. It returns the value of the
#'   variable when it is called, and stops with an error that names the
#'   variable when it is empty. With `key = NULL` it returns `NULL`.
#' @noRd
env_credentials <- function(key) {
  if (is.null(key)) {
    return(function() NULL)
  }
  function() {
    value <- Sys.getenv(key)
    if (!nzchar(value)) {
      cli::cli_abort(c(
        "No API key: the environment variable {.envvar {key}} is empty.",
        i = "Set it, or give the decider a {.arg credentials} function."
      ))
    }
    value
  }
}

#' Use the default model when none is given
#'
#' Prints the default model, as ellmer does, so that the user sees which
#' name to change when a provider retires a model.
#'
#' @param model The model of the user, or `NULL`.
#' @param default The default model.
#' @return `model`, or `default` when `model` is `NULL`.
#' @noRd
default_model <- function(model, default) {
  if (!is.null(model)) {
    return(model)
  }
  cli::cli_inform("Using {.field model} = {.val {default}}.")
  default
}

#' Name the provider of a decider in a message
#'
#' @param decider A decider.
#' @return `"TypeSafe"`, `"OpenAI"`, `"Microsoft Foundry"`, `"OpenRouter"`
#'   or `"The server at <base_url>"`.
#' @noRd
provider_name <- function(decider) {
  switch(decider@provider,
    typesafe = "TypeSafe",
    openai = "OpenAI",
    foundry = "Microsoft Foundry",
    openrouter = "OpenRouter",
    paste("The server at", decider@base_url)
  )
}

#' Find the request URL of a decider
#'
#' @param decider A decider.
#' @return The server root with the path of the provider appended.
#' @noRd
decider_url <- function(decider) {
  path <- switch(decider@provider,
    openai = "v1/decisions",
    openrouter = "api/alpha/decisions",
    foundry = "providers/microsoft/v1/systemone",
    "v1/systemone"
  )
  paste0(sub("/+$", "", decider@base_url), "/", path)
}

# Constructors --------------------------------------------------------------

#' Use Jev through the TypeSafe API
#'
#' Makes a decider for a Jev model on the TypeSafe API
#' (`https://api.typesafe.ai`, SystemOne format).
#'
#' @param model The model name, for example `"jev-1.13.0"`. `NULL` (the
#'   default) uses `"jev-latest"` and prints a message that names it.
#' @param credentials A function with no arguments that returns the key, for
#'   example to read it from a secret store. `NULL` (the default) reads the
#'   environment variable `TYPESAFE_API_KEY` each time `decide()` sends
#'   requests.
#' @param input The input type that the model reads: `"text"`, `"image"` or
#'   `"text+image"`. `NULL` (the default) takes it from the internal table of
#'   input types; a model that is not in the table is not checked. `decide()`
#'   stops before any request when an input does not fit.
#' @return A decider object for `decide()`. It holds no key.
#' @details Image input is experimental: TypeSafe reads images only with the
#'   header `TypeSafe-Danger-Zone-Images: true`, which `decide()` sends
#'   whenever a request carries an image. TypeSafe does not report a cost, so
#'   `.cost` is `NA` in the output of `decide()`. On 2026-10-23, TypeSafe
#'   refused images under 280 pixels on the longest side. So use
#'   `upscale = TRUE` for small images (see `vignette("images")`).
#' @examples
#' decider_typesafe("jev-1.13.0")
#' # A function can give the key, for example from another variable:
#' decider_typesafe("jev-1.13.0", credentials = \() Sys.getenv("MY_JEV_KEY"))
#' @export
decider_typesafe <- function(model = NULL, credentials = NULL, input = NULL) {
  new_decider(
    provider = "typesafe",
    format = "systemone",
    base_url = "https://api.typesafe.ai",
    model = default_model(model, "jev-latest"),
    input = input,
    credentials = credentials,
    image_format = "assets"
  )
}

#' Use the OpenAI Decisions API
#'
#' Makes a decider for a model of the OpenAI Decisions API
#' (`https://api.openai.com`).
#'
#' @param model The model name. `NULL` (the default) uses `"gpt-6-luna"` and
#'   prints a message that names it.
#' @param credentials A function with no arguments that returns the key.
#'   `NULL` (the default) reads the environment variable `OPENAI_API_KEY`
#'   each time `decide()` sends requests.
#' @inheritParams decider_typesafe
#' @return A decider object for `decide()`. It holds no key.
#' @details OpenAI does not report a cost, so `.cost` is `NA` in the output
#'   of `decide()`.
#' @examples
#' decider_openai("gpt-6-luna")
#' @export
decider_openai <- function(model = NULL, credentials = NULL, input = NULL) {
  new_decider(
    provider = "openai",
    format = "openai",
    base_url = "https://api.openai.com",
    model = default_model(model, "gpt-6-luna"),
    input = input,
    credentials = credentials
  )
}

#' Use Microsoft-Decision-1 on Microsoft Foundry
#'
#' Makes a decider for a deployment of Microsoft-Decision-1 on Microsoft
#' Foundry (SystemOne format).
#'
#' @param endpoint The endpoint of the Foundry resource, for example
#'   `"https://<resource>.services.ai.azure.com"`. The default reads the
#'   environment variable `AZURE_FOUNDRY_ENDPOINT`.
#' @param deployment The name of the deployment. It is the model name of the
#'   request.
#' @param credentials A function with no arguments that returns the key.
#'   `NULL` (the default) reads the environment variable
#'   `AZURE_FOUNDRY_API_KEY` each time `decide()` sends requests.
#' @inheritParams decider_typesafe
#' @return A decider object for `decide()`. It holds no key.
#' @details The requests go to `<endpoint>/providers/microsoft/v1/systemone`
#'   with the key in the `api-key` header. This decider is not yet tested
#'   with a live call. Microsoft-Decision-1 reads text only.
#' @examples
#' decider_foundry("https://my-resource.services.ai.azure.com", "decision-1")
#' @export
decider_foundry <- function(endpoint = Sys.getenv("AZURE_FOUNDRY_ENDPOINT"),
                            deployment, credentials = NULL, input = NULL) {
  rlang::check_required(deployment)
  if (!rlang::is_string(endpoint) || !nzchar(endpoint)) {
    cli::cli_abort(paste(
      "Give {.arg endpoint}, or set the environment variable",
      "{.envvar AZURE_FOUNDRY_ENDPOINT}."
    ))
  }
  new_decider(
    provider = "foundry",
    format = "systemone",
    base_url = endpoint,
    model = deployment,
    input = input,
    credentials = credentials,
    image_format = "assets"
  )
}

#' Use a decision model through OpenRouter
#'
#' Makes a decider for a decision model on OpenRouter
#' (`https://openrouter.ai`, alpha decisions endpoint), for example Jev or
#' Microsoft-Decision-1.
#'
#' @param model The OpenRouter model id, for example `"typesafe/jev-1.14"`
#'   or `"microsoft/microsoft-decision-1"`. Required.
#' @param credentials A function with no arguments that returns the key.
#'   `NULL` (the default) reads the environment variable
#'   `OPENROUTER_API_KEY` each time `decide()` sends requests.
#' @inheritParams decider_typesafe
#' @return A decider object for `decide()`. It holds no key.
#' @details OpenRouter documents no image field for decisions, so the table
#'   of input types gives every OpenRouter model the input type `"text"`.
#'   OpenRouter reports the cost of each call, and `.cost` holds it.
#' @examples
#' decider_openrouter("typesafe/jev-1.14")
#' @export
decider_openrouter <- function(model, credentials = NULL, input = NULL) {
  rlang::check_required(model)
  new_decider(
    provider = "openrouter",
    format = "openrouter",
    base_url = "https://openrouter.ai",
    model = model,
    input = input,
    credentials = credentials
  )
}

#' Use any SystemOne server
#'
#' Makes a decider for a server that speaks SystemOne, for example
#' Clef-Flash on an SGLang server or Laya on `laya-serve`, often on the
#' computer of the user.
#'
#' @param base_url The server root, for example `"http://localhost:30000"`.
#'   Requests go to `<base_url>/v1/systemone`.
#' @param model The model name, for example `"Cloudflare/clef-flash"`, or a
#'   Laya checkpoint (`"english"`, `"multilingual"`, `"typed-decisions"`).
#'   Required.
#' @param image_format How the server takes images: `"assets"` (the
#'   SystemOne `assets` object) or `"images"` (an ordered list of images, as
#'   the SGLang server of Clef-Flash needs).
#' @param credentials A function with no arguments that returns a key. `NULL`
#'   (the default) sends no key, as a local server needs none. With a
#'   function, the key goes in an `Authorization: Bearer` header.
#' @inheritParams decider_typesafe
#' @return A decider object for `decide()`. It holds no key.
#' @details With `image_format = "images"`, `decide()` writes every image
#'   with three color channels, because the SGLang server cannot read a JPEG
#'   with one channel.
#' @examples
#' decider_systemone(
#'   "http://localhost:30000", "Cloudflare/clef-flash", image_format = "images"
#' )
#' decider_systemone("http://localhost:8000", "typed-decisions")
#' @export
decider_systemone <- function(base_url, model,
                              image_format = c("assets", "images"),
                              credentials = NULL, input = NULL) {
  rlang::check_required(base_url)
  rlang::check_required(model)
  image_format <- rlang::arg_match(image_format)
  new_decider(
    provider = "systemone",
    format = if (image_format == "images") "systemone_images" else "systemone",
    base_url = base_url,
    model = model,
    input = input,
    credentials = credentials,
    image_format = image_format
  )
}
