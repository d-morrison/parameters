#' @title Robust estimation
#' @name standard_error_robust
#'
#' @description `standard_error_robust()`, `ci_robust()` and `p_value_robust()`
#' attempt to return indices based on robust estimation of the variance-covariance
#' matrix, using the packages \pkg{sandwich} and \pkg{clubSandwich}.
#'
#' @param model A model.
#' @param vcov_estimation String, indicating the suffix of the
#'   `vcov*()`-function from the \pkg{sandwich} or \pkg{clubSandwich}
#'   package, e.g. `vcov_estimation = "CL"` (which calls
#'   [sandwich::vcovCL()] to compute clustered covariance matrix
#'   estimators), or `vcov_estimation = "HC"` (which calls
#'   [sandwich::vcovHC()] to compute
#'   heteroskedasticity-consistent covariance matrix estimators).
#' @param vcov_type Character vector, specifying the estimation type for the
#'   robust covariance matrix estimation (see
#'   [sandwich::vcovHC()] or `clubSandwich::vcovCR()`
#'   for details). Passed down as `type` argument to the related `vcov*()`-function
#'   from the  \pkg{sandwich} or \pkg{clubSandwich} package and hence will be
#'   ignored if there is no `type` argument (e.g., `sandwich::vcovHAC()` will
#'   ignore that argument).
#' @param vcov_args List of named vectors, used as additional arguments that are
#'   passed down to the \pkg{sandwich}-function specified in
#'   `vcov_estimation`.
#' @param component Should all parameters or parameters for specific model
#'   components be returned?
#' @param ... Arguments passed to or from other methods. For
#'   `standard_error()`, if `method = "robust"`, arguments
#'   `vcov_estimation`, `vcov_type` and `vcov_args` can be passed
#'   down to `standard_error_robust()`.
#' @inheritParams ci.default
#'
#' @note These functions rely on the \pkg{sandwich} or \pkg{clubSandwich} package
#'   (the latter if `vcov_estimation = "CR"` for cluster-robust standard errors)
#'   and will thus only work for those models supported by those packages.
#'
#' @seealso Working examples cam be found [in this vignette](https://easystats.github.io/parameters/articles/model_parameters_robust.html).
#'
#' @examples
#' if (require("sandwich", quietly = TRUE)) {
#'   # robust standard errors, calling sandwich::vcovHC(type="HC3") by default
#'   model <- lm(Petal.Length ~ Sepal.Length * Species, data = iris)
#'   standard_error_robust(model)
#' }
#' \dontrun{
#' if (require("clubSandwich", quietly = TRUE)) {
#'   # cluster-robust standard errors, using clubSandwich
#'   iris$cluster <- factor(rep(LETTERS[1:8], length.out = nrow(iris)))
#'   standard_error_robust(
#'     model,
#'     vcov_type = "CR2",
#'     vcov_args = list(cluster = iris$cluster)
#'   )
#' }
#' }
#' @return A data frame.
#' @export
standard_error_robust <- function(model,
                                  vcov_estimation = "HC",
                                  vcov_type = NULL,
                                  vcov_args = NULL,
                                  component = "conditional",
                                  ...) {
  # exceptions
  if (inherits(model, "gee")) {
    return(standard_error(model, robust = TRUE, ...))
  }

  if (inherits(model, "MixMod")) {
    return(standard_error(model, robust = TRUE, ...))
  }


  # check for existing vcov-prefix
  if (!grepl("^(vcov|kernHAC|NeweyWest)", vcov_estimation)) {
    vcov_estimation <- paste0("vcov", vcov_estimation)
  }

  robust <- .robust_covariance_matrix(
    model,
    vcov_fun = vcov_estimation,
    vcov_type = vcov_type,
    vcov_args = vcov_args,
    component = component
  )

  if ("Component" %in% colnames(robust) && .n_unique(robust$Component) > 1) {
    cols <- c("Parameter", "SE", "Component")
  } else {
    cols <- c("Parameter", "SE")
  }
  robust[, cols]
}



#' @rdname standard_error_robust
#' @export
p_value_robust <- function(model,
                           vcov_estimation = "HC",
                           vcov_type = NULL,
                           vcov_args = NULL,
                           component = "conditional",
                           method = NULL,
                           ...) {
  # exceptions
  if (inherits(model, "gee")) {
    return(p_value(model, robust = TRUE, ...))
  }

  if (inherits(model, "MixMod")) {
    return(p_value(model, robust = TRUE, ...))
  }


  # check for existing vcov-prefix
  if (!grepl("^(vcov|kernHAC|NeweyWest)", vcov_estimation)) {
    vcov_estimation <- paste0("vcov", vcov_estimation)
  }

  robust <- .robust_covariance_matrix(
    model,
    vcov_fun = vcov_estimation,
    vcov_type = vcov_type,
    vcov_args = vcov_args,
    component = component,
    method = method
  )

  if ("Component" %in% colnames(robust) && .n_unique(robust$Component) > 1) {
    cols <- c("Parameter", "p", "Component")
  } else {
    cols <- c("Parameter", "p")
  }
  robust[, cols]
}


#' @rdname standard_error_robust
#' @export
ci_robust <- function(model,
                      ci = 0.95,
                      method = NULL,
                      vcov_estimation = "HC",
                      vcov_type = NULL,
                      vcov_args = NULL,
                      component = "conditional",
                      ...) {
  out <- .ci_generic(
    model = model,
    ci = ci,
    method = method,
    component = component,
    robust = TRUE,
    vcov_estimation = vcov_estimation,
    vcov_type = vcov_type,
    vcov_args = vcov_args
  )

  if ("Component" %in% colnames(out) && .n_unique(out$Component) == 1) {
    out$Component <- NULL
  }
  out
}


.robust_covariance_matrix <- function(x,
                                      vcov_fun = "vcovHC",
                                      vcov_type = NULL,
                                      vcov_args = NULL,
                                      component = "conditional",
                                      method = "any") {
  # fix default, if necessary
  if (!is.null(vcov_type) && vcov_type %in% c("CR0", "CR1", "CR1p", "CR1S", "CR2", "CR3")) {
    vcov_fun <- "vcovCR"
  }

  # set default for clubSandwich
  if (vcov_fun == "vcovCR" && is.null(vcov_type)) {
    vcov_type <- "CR0"
  }

  # check if required package is available
  if (vcov_fun == "vcovCR") {
    insight::check_if_installed("clubSandwich", reason = "to get cluster-robust standard errors")
    .vcov <- do.call(clubSandwich::vcovCR, c(list(obj = x, type = vcov_type), vcov_args))
  } else {
    insight::check_if_installed("sandwich", reason = "to get robust standard errors")
    vcov_fun <- get(vcov_fun, asNamespace("sandwich"))
    .vcov <- do.call(vcov_fun, c(list(x = x, type = vcov_type), vcov_args))
  }

  # get coefficients
  params <- insight::get_parameters(x, component = component, verbose = FALSE)

  if (!is.null(component) && component != "all" && nrow(.vcov) > nrow(params)) {
    keep <- match(insight::find_parameters(x)[[component]], rownames(.vcov))
    .vcov <- .vcov[keep, keep, drop = FALSE]
  }

  if (is.null(method)) {
    method <- "any"
  }

  se <- sqrt(diag(.vcov))
  dendf <- degrees_of_freedom(x, method = method)
  t.stat <- params$Estimate / se

  if (is.null(dendf)) {
    p.value <- 2 * stats::pnorm(abs(t.stat), lower.tail = FALSE)
  } else {
    p.value <- 2 * stats::pt(abs(t.stat), df = dendf, lower.tail = FALSE)
  }


  out <- .data_frame(
    Parameter = params$Parameter,
    Estimate = params$Estimate,
    SE = se,
    Statistic = t.stat,
    p = p.value
  )

  if (!is.null(params$Component) && nrow(params) == nrow(out)) {
    out$Component <- params$Component
  }
  out
}
