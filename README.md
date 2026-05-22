# SeaLevelTools

**Sea Level Adjustment and Coastal Terrain Modeling for R**

`SeaLevelTools` is an R package for simulating sea-level rise and fall using raster-based elevation models. It enables vertical datum transformations of Digital Terrain Models (DTMs), integration of bathymetric data, and generation of continuous terrestrial–marine Digital Elevation Models (DEMs).

The package is designed for applications in:

- Coastal engineering
- Paleogeographic reconstruction
- Archaeological landscape exposure modeling
- Climate change impact assessment
- Environmental modeling
- Geospatial analysis
- Geomorphology


## Features

- Simulate sea-level rise and fall
- Merge terrestrial terrain with bathymetric data
- Generate continuous DEMs
- Apply threshold-based terrain filtering
- Optional iterative gap-filling for incomplete surfaces
- Crop analyses to custom study areas
- Export processed rasters directly to disk
- Visualization support for elevation modeling results


## Installation

### Install from GitHub

```r
# install.packages("remotes")
remotes::install_github("yourusername/sealeveltools")
```

### Dependencies

The package currently depends on:

```r
install.packages(c("terra"))
```


## Main Function

### `adjustSeaLevel()`

`adjustSeaLevel()` recalculates terrain elevations relative to a modified sea-level datum.

### Functionality

The function can:

- Raise or lower sea level
- Merge DTM and bathymetric rasters
- Reconstruct missing terrain through iterative focal interpolation
- Remove terrain below a specified elevation threshold
- Visualize adjusted elevation models
- Export results to raster formats


## Function Arguments

| Argument | Description |
|---|---|
| `dtm` | `SpatRaster` Digital Terrain Model |
| `seaLevelChange` | Numeric sea-level change value (positive = rise, negative = fall) |
| `bathymetry` | Optional bathymetric `SpatRaster` |
| `studyArea` | Optional polygon boundary (`SpatVector`) |
| `fillGaps` | Logical option for iterative gap-filling |
| `removeUnder` | Remove elevations below threshold |
| `plot` | Plot results |
| `filename` | Output filename |
| `overwrite` | Overwrite existing files |
| `wopt` | Additional write options |


## Example Workflow

```r
library(terra)
library(sealeveltools)

### Create dummy DTM and Bathymetric data ###

nr <- 300
nc <- 300

lon <- seq(-10, 10, length.out = nc)
lat <- seq(-10, 10, length.out = nr)

data_mat <- matrix(NA, nrow = nr, ncol = nc)

for (i in 1:nr) {
  for (j in 1:nc) {
    terrain <- 500 * exp(-(lon[j]^2 + lat[i]^2) / 10)
    data_mat[i, j] <- -1000 +
      1000 * exp(-(lon[j]^2 + lat[i]^2) / 50) +
      terrain +
      rnorm(1, 0, 5)
  }
}

### Create raster ###

rast_demo <- rast(
  ncols = 300,
  nrows = 300,
  xmin = 0,
  xmax = 300,
  ymin = 0,
  ymax = 300
)

values(rast_demo) <- data_mat

### Separate DTM and bathymetry ###

dtm_demo <- rast_demo
dtm_demo[dtm_demo[] <= 0] <- NA

bathy_demo <- rast_demo
bathy_demo[bathy_demo[] > 0] <- NA

### Simulate sea-level rise ###

dtm_rise <- adjustSeaLevel(
  dtm = dtm_demo,
  seaLevelChange = 100,
  plot = TRUE
)

### Simulate sea-level fall ###

dtm_lower <- adjustSeaLevel(
  dtm = dtm_demo,
  seaLevelChange = -100,
  bathymetry = bathy_demo,
  plot = TRUE
)
```


### Gap Filling Example

```r
### Introduce missing data ###

dtm_demo[dtm_demo[] <= 3] <- NA

### Reconstruct terrain ###

dtm_lower_filled <- adjustSeaLevel(
  dtm = dtm_demo,
  seaLevelChange = -50,
  bathymetry = bathy_demo,
  fillGaps = TRUE,
  plot = TRUE
)
```


### Output Visualization

The package includes built-in visualization support using elevation-based color ramps for rapid interpretation of modeled terrain changes.

Typical outputs include:

- Coastal inundation maps
- Exposed paleolandscape reconstructions
- Continuous land–sea DEMs
- Terrain suitability masks


## Package Structure

```text
sealeveltools/
├── R/
│   └── adjustSeaLevel.R
├── DESCRIPTION
├── NAMESPACE
├── README.md
└── man/
```


## Authors

### Jovan Kovačević
- University of Belgrade, Faculty of Civil Engineering
- Email: jkovacevic@grf.bg.ac.rs
- ORCID: 0000-0001-9980-5797

### Christopher Nuttall
- Swedish Institute at Athens
- Email: chrisnuttallacademia@gmail.com
- ORCID: 0000-0003-2679-9677


## License

GPL (>= 3)
