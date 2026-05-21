#' Adjust terrain elevations relative to sea-level change
#'
#' @description
#' `adjustSeaLevel()` recalculates terrain elevations relative to a modified
#' sea-level datum. The function simulates sea-level rise or fall by shifting
#' elevation values accordingly.
#'
#' If bathymetric data is provided, submerged terrain is merged with the DTM
#' to produce a continuous DEM. This is particularly useful for: coastal engineering studies,
#' paleogeographic reconstructions, archaeological landscape exposure modelling and climate change impact assessments.
#'
#' Optional gap-filling enables reconstruction of missing terrain areas
#' through iterative focal interpolation.
#'
#' @param dtm `SpatRaster`: Digital Terrain Model.
#' @param seaLevelChange `numeric`: Sea level change value.
#'        Positive = sea level rise.
#'        Negative = sea level drop.
#' @param bathymetry `SpatRaster` (optional): Bathymetric raster to merge with DTM.
#' @param studyArea `SpatVector` (optional):  Study area polygon to which to crop results.
#' @param fillGaps `logical` (default `FALSE`): Whether to iteratively fill NA gaps.
#' @param removeUnder `numeric` (optional): If specified, removes all elevations under defined threshold.
#' @param plot `logical` (default `FALSE`): Whether to visualize results
#' @param filename `character` (optional): Output file name, skipped if left empty
#' @param overwrite `logical` (default `FALSE`): If `TRUE`, `filename` is overwritten
#' @param wopt `list()`: list with named options for writing files as in `writeRaster`
#'
#' @returns `SpatRaster`: DEM adjusted for sea level change.
#'
#' @examples
#' library(terra)
#'
#' ### Create dummy DTM and Bathymetric data ###
#' nr <- 300
#' nc <- 300
#' lon <- seq(-10, 10, length.out = nc)
#' lat <- seq(-10, 10, length.out = nr)
#'
#  ### Create a base Gaussian surface: underwater with terrain in the center ###
#' data_mat <- matrix(NA, nrow = nr, ncol = nc)
#' for (i in 1:nr) {
#'   for (j in 1:nc) {
#'     terrain <- 500 * exp(-(lon[j]^2 + lat[i]^2) / 10)
#'     data_mat[i, j] <- -1000 + 1000 * exp(-(lon[j]^2 + lat[i]^2) / 50) + terrain + rnorm(1, 0, 5)
#'   }
#' }
#'
#' ### Create SpatRast data ###
#' rast_demo <- rast(ncols = 300, nrows = 300, xmin = 0, xmax = 300, ymin = 0, ymax = 300)
#' values(rast_demo) <- data_mat
#'
#' dtm_demo <- rast_demo
#' dtm_demo[dtm_demo[] <= 0] <- NA
#' # plot(dtm_demo)
#'
#' bathy_demo <- rast_demo
#' bathy_demo[bathy_demo[] > 0] <- NA
#' # plot(bathy_demo)
#'
#' ### Rise sea level ###
#' dtm_rise <- adjustSeaLevel(dtm = dtm_demo, seaLevelChange = 100, plot = TRUE)
#'
#' ### Lower sea level with bathymetric data ###
#' dtm_lower <- adjustSeaLevel(
#'   dtm = dtm_demo, seaLevelChange = -100,
#'   bathy = bathy_demo, plot = TRUE
#' )
#'
#' ### Lower sea level with bathymetric data and remove areas under -500 ###
#' dtm_lower <- adjustSeaLevel(
#'   dtm = dtm_demo, seaLevelChange = -100,
#'   bathy = bathy_demo, removeUnder = -500, plot = TRUE
#' )
#'
#' ### Lower sea level with bathymetric data and gap-filling ###
#' dtm_demo[dtm_demo[] <= 3] <- NA # introduce missing data
#' dtm_lower_gaps <- adjustSeaLevel(
#'   dtm = dtm_demo, seaLevelChange = -50,
#'   bathy = bathy_demo, plot = TRUE
#' )
#' dtm_lower_filled <- adjustSeaLevel(
#'   dtm = dtm_demo, seaLevelChange = -50,
#'   bathy = bathy_demo, fillGaps = TRUE, plot = TRUE
#' )
#'

#' @export
adjustSeaLevel <- function(
  dtm,
  seaLevelChange,
  bathymetry = NULL,
  studyArea = NULL,
  fillGaps = FALSE,
  removeUnder = NULL,
  plot = FALSE,
  filename = "",
  overwrite = FALSE,
  wopt = list()
) {
  ## -----------------------------
  ## 1. Input validation
  ## -----------------------------

  if (!inherits(dtm, "SpatRaster")) {
    stop("dtm must be a SpatRaster.")
  }

  if (!is.numeric(seaLevelChange) || length(seaLevelChange) != 1) {
    stop("seaLevelChange must be a single numeric value.")
  }

  if (!is.null(bathymetry) && !inherits(bathymetry, "SpatRaster")) {
    stop("bathymetry must be a SpatRaster.")
  }

  if (!is.null(studyArea) && !inherits(studyArea, "SpatVector")) {
    stop("studyArea must be a SpatVector.")
  }

  ## -----------------------------
  ## 2. Crop to study area
  ## -----------------------------

  if (!is.null(studyArea)) {
    studyArea_proj <- terra::project(studyArea, terra::crs(dtm))
    dtm <- terra::crop(dtm, studyArea_proj)

    if (!is.null(bathymetry)) {
      bathymetry <- terra::project(bathymetry, terra::crs(dtm))
      bathymetry <- terra::crop(bathymetry, studyArea_proj)
    }
  }


  ## -----------------------------
  ## 3. Merge DTM + bathymetry
  ## -----------------------------

  if (!is.null(bathymetry)) {
    # Geometric compatibility (CRS + resolution + origin check)
    if (!terra::compareGeom(dtm, bathymetry, crs = TRUE, stopOnError = FALSE)) {
      bathymetry <- terra::project(bathymetry, terra::crs(dtm))
    }

    # Create union extent
    dtm_ext <- terra::ext(dtm)
    bathy_ext <- terra::ext(bathymetry)
    ext_merge <- terra::union(dtm_ext, bathy_ext)

    dtm <- terra::extend(dtm, ext_merge)
    bathymetry <- terra::extend(bathymetry, ext_merge)

    # Match resolution (resample bathymetry to DTM grid)
    if (!terra::compareGeom(dtm, bathymetry, res = TRUE, stopOnError = FALSE)) {
      bathymetry <- terra::resample(bathymetry, dtm, method = "bilinear")
    }

    # Remove non-submerged bathymetry values
    bathymetry[bathymetry >= 0] <- NA

    # Merge using minimum elevation
    new_dtm <- terra::mosaic(dtm, bathymetry, fun = "min")
  } else {
    new_dtm <- dtm
  }


  ## -----------------------------
  ## 4. Optional gap filling
  ## -----------------------------

  if (fillGaps) {
    max_iter <- 15
    iter <- 1

    na_cells <- sum(is.na(terra::values(new_dtm)))

    while (na_cells > 0 && iter <= max_iter) {
      w_size <- 1 + 2 * iter

      new_dtm <- terra::focal(
        new_dtm,
        w = w_size,
        fun = mean,
        na.rm = TRUE,
        na.policy = "only"
      )

      na_cells <- sum(is.na(terra::values(new_dtm)))
      iter <- iter + 1
    }

    # Mask out areas outside dtm and bathymetry extents
    new_dtm <- terra::mask(new_dtm, terra::union(
      terra::as.polygons(dtm_ext, crs = terra::crs(dtm)),
      terra::as.polygons(bathy_ext, crs = terra::crs(bathymetry))
    ))
  }


  ## -----------------------------
  ## 5. Apply sea-level datum shift
  ## -----------------------------

  new_dtm <- new_dtm - seaLevelChange

  ## -----------------------------
  ## 6. Remove values below threshold
  ## -----------------------------

  if (!is.null(removeUnder)) {
    if (!is.numeric(removeUnder) || length(removeUnder) != 1) {
      stop("removeUnder must be a single numeric value.")
    }

    new_dtm[new_dtm < removeUnder] <- NA
  }


  ## -----------------------------
  ## 7. Optional plotting
  ## -----------------------------

  if (plot) {
    elev_sign <- ifelse(seaLevelChange > 0, "+", "")

    col_breaks <- c(-1000, -500, -200, -100, -50, 0, 50, 100, 200, 500, 1000, 1500, 2000)
    colours_list <- c(grDevices::topo.colors(100)[1:33], grDevices::terrain.colors(66))

    terra::plot(new_dtm,
      breaks = col_breaks, col = colours_list, fill_range = T, type = "continuous",
      main = paste0("Sea Level Adjustment (", elev_sign, seaLevelChange, " m)"), plg = list(title = "Elevation [m]")
    )
  }

  ## -----------------------------
  ## 8. Optional export
  ## -----------------------------

  if (nzchar(filename)) {
    terra::writeRaster(
      new_dtm,
      filename = filename,
      overwrite = overwrite,
      wopt = wopt
    )
  }

  return(new_dtm)
}
