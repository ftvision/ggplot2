#' @include legend-draw.r
NULL

#' @section Geoms:
#'
#' All \code{geom_*} functions (like \code{geom_point}) return a layer that
#' contains a \code{Geom*} object (like \code{GeomPoint}). The \code{Geom*}
#' object is responsible for rendering the data in the plot.
#'
#' Each of the \code{Geom*} objects is a \code{\link{ggproto}} object, descended
#' from the top-level \code{Geom}, and each implements various methods and
#' fields. To create a new type of Geom object, you typically will want to
#' implement one or more of the following:
#'
#' Compared to \code{Stat} and \code{Position}, \code{Geom} is a little
#' different because the execution of the setup and compute functions is
#' split up. \code{setup_data} runs before position adjustments, and
#' \code{draw_layer} is not run until render time,  much later. This
#' means there is no \code{setup_params} because it's hard to communicate
#' the changes.
#'
#' \itemize{
#'   \item Override either \code{draw_panel(self, data, panel_scales, coord)} or
#'     \code{draw_group(self, data, panel_scales, coord)}. \code{draw_panel} is
#'     called once per panel, \code{draw_group} is called once per group.
#'
#'     Use \code{draw_panel} if each row in the data represents a
#'     single element. Use \code{draw_group} if each group represents
#'     an element (e.g. a smooth, a violin).
#'
#'     \code{data} is a data frame of scaled aesthetics. \code{panel_scales}
#'     is a list containing information about the scales in the current
#'     panel. \code{coord} is a coordinate specification. You'll
#'     need to call \code{coord$transform(data, panel_scales)} to work
#'     with non-Cartesian coords. To work with non-linear coordinate systems,
#'     you typically need to convert into a primitive geom (e.g. point, path
#'     or polygon), and then pass on to the corresponding draw method
#'     for munching.
#'
#'     Must return a grob. Use \code{\link{zeroGrob}} if there's nothing to
#'     draw.
#'   \item \code{draw_key}: Renders a single legend key.
#'   \item \code{required_aes}: A character vector of aesthetics needed to
#'     render the geom.
#'   \item \code{default_aes}: A list (generated by \code{\link{aes}()} of
#'     default values for aesthetics.
#'   \item \code{reparameterise}: Converts width and height to xmin and xmax,
#'     and ymin and ymax values. It can potentially set other values as well.
#' }
#' @rdname ggplot2-ggproto
#' @format NULL
#' @usage NULL
#' @export
Geom <- ggproto("Geom",
  required_aes = character(),
  non_missing_aes = character(),

  default_aes = aes(),

  draw_key = draw_key_point,

  handle_na = function(self, data, params) {
    remove_missing(data, params$na.rm,
      c(self$required_aes, self$non_missing_aes),
      snake_class(self)
    )
  },

  draw_layer = function(self, data, params, panel, coord) {
    if (empty(data)) {
      n <- nlevels(data$PANEL)
      return(rep(list(zeroGrob()), n))
    }

    # Trim off extra parameters
    params <- params[intersect(names(params), self$parameters())]

    args <- c(list(quote(data), quote(panel_scales), quote(coord)), params)
    plyr::dlply(data, "PANEL", function(data) {
      if (empty(data)) return(zeroGrob())

      panel_scales <- panel$ranges[[data$PANEL[1]]]
      do.call(self$draw_panel, args)
    }, .drop = FALSE)
  },

  draw_panel = function(self, data, panel_scales, coord, ...) {
    groups <- split(data, factor(data$group))
    grobs <- lapply(groups, function(group) {
      self$draw_group(group, panel_scales, coord, ...)
    })

    ggname(snake_class(self), gTree(
      children = do.call("gList", grobs)
    ))
  },

  draw_group = function(self, data, panel_scales, coord) {
    stop("Not implemented")
  },

  setup_data = function(data, params) data,

  # Combine data with defaults and set aesthetics from parameters
  use_defaults = function(self, data, params = list()) {
    # Fill in missing aesthetics with their defaults
    missing_aes <- setdiff(names(self$default_aes), names(data))
    if (empty(data)) {
      data <- plyr::quickdf(self$default_aes[missing_aes])
    } else {
      data[missing_aes] <- self$default_aes[missing_aes]
    }

    # Override mappings with params
    aes_params <- intersect(self$aesthetics(), names(params))
    check_aesthetics(params[aes_params], nrow(data))
    data[aes_params] <- params[aes_params]
    data
  },

  # Most parameters for the geom are taken automatically from draw_panel() or
  # draw_groups(). However, some additional parameters may be needed
  # for setup_data() or handle_na(). These can not be imputed automatically,
  # so the slightly hacky "extra_params" field is used instead. By
  # default it contains `na.rm`
  extra_params = c("na.rm"),

  parameters = function(self, extra = FALSE) {
    # Look first in draw_panel. If it contains ... then look in draw groups
    panel_args <- names(ggproto_formals(self$draw_panel))
    group_args <- names(ggproto_formals(self$draw_group))
    args <- if ("..." %in% panel_args) group_args else panel_args

    # Remove arguments of defaults
    args <- setdiff(args, names(ggproto_formals(Geom$draw_group)))

    if (extra) {
      args <- union(args, self$extra_params)
    }
    args
  },

  aesthetics = function(self) {
    c(union(self$required_aes, names(self$default_aes)), "group")
  }

)


#' Graphical units
#'
#' Multiply size in mm by these constants in order to convert to the units
#' that grid uses internally for \code{lwd} and \code{fontsize}.
#'
#' @name graphical-units
NULL

#' @export
#' @rdname graphical-units
.pt <- 72.27 / 25.4
#' @export
#' @rdname graphical-units
.stroke <- 96 / 25.4

check_aesthetics <- function(x, n) {
  ns <- vapply(x, length, numeric(1))
  good <- ns == 1L | ns == n

  if (all(good)) {
    return()
  }

  stop(
    "Aesthetics must be either length 1 or the same as the data (", n, "): ",
    paste(names(!good), collapse = ", "),
    call. = FALSE
  )
}
