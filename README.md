# methylCC

This is a package to estimate the cell composition 
    of bulk DNA methylation measured on any 
    platform technology (e.g. Illumina 450K microarray, 
    whole genome bisulfite sequencing (WGBS) and 
    reduced representation bisulfite sequencing (RRBS))
    using reference cell-type-specific methylation data. 

For help with the **methylCC** R-package, there is a vignette available in the /vignettes folder.

### Updates from the original version

28/01/2021:
* Added the option to use already processed methylation data 
(eg: normalized beta values).  
* New function *find_dmrs_cust()* for finding Differentially Methylated Regions (DMRs) from
custom reference-cell-type-specific methylation data (esp: in tissues other than Whole Blood)
  
### Installing methylCC

The R-package **methylCC** can be installed from Github using the R 
package [devtools](https://github.com/hadley/devtools): 

To install the tinkered version of **methylCC** from Github:
```s
library(devtools)
install_github("lbroseus/methylCC")
```

After installation, the package can be loaded into R.
```s
library(methylCC)
```

### Installing the original version of methylCC

To install the original version of **methylCC** from Github:

```s
library(devtools)
install_github("stephaniehicks/methylCC")
```

### Citation 

Hicks SC, Irizarry RA. (2019). _Genome Biology_ **20**, 261. [https://doi.org/10.1186/s13059-019-1827-8](https://doi.org/10.1186/s13059-019-1827-8)

# Authors

* [Stephanie C. Hicks](https://github.com/stephaniehicks)
* [Rafael A. Irizarry](https://github.com/ririzarr)
