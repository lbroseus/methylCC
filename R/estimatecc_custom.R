# methylCC: 
# Adapted from R/estimatecc.R to allow custom cell-type-specific reference
#
# Author: Lucile Broseus
# Date: 28/01/2020
#########################################################

#' @title Estimate reference-cell composition from DNAm data
#'
#' @description Estimate cell composition from DNAm data
#'
#' @param object an object can be a \code{RGChannelSet}, 
#' \code{GenomicMethylSet}, \code{BSseq} or a \code{GenomicRatioSet} object
#' @param find_dmrs_object User-supplied differentially methylated regions from
#' reference cell types  as output from the \code{find_dmrs_custom} function.
#' @param verbose TRUE/FALSE argument specifying if verbose
#' messages should be returned or not. Default is TRUE.
#' @param epsilon Threshold for EM algorithm to check
#' for convergence. Default is 0.01.
#' @param max_iter Maximum number of iterations for EM
#' algorithm. Default is 100 iterations.
#' @param take_intersection TRUE/FALSE asking if only the CpGs 
#' included in \code{object} should be used to find DMRs. 
#' Default is FALSE.
#' @param include_cpgs TRUE/FALSE. Should individual CpGs
#' be returned. Default is FALSE. 
#' @param include_dmrs TRUE/FALSE. Should differentially 
#' methylated regions be returned. Default is TRUE. 
#' @param init_param_method method to initialize parameter estimates.
#' Choose between "random" (randomly sample) or "known_regions"
#' (uses unmethyalted and methylated regions that were identified
#' based on Reinus et al. (2012) cell sorted data.).
#' Defaults to "random".
#' @param a0init Default NULL. Initial mean 
#' methylation level in unmethylated regions
#' @param a1init Default NULL. Initial mean 
#' methylation level in methylated regions
#' @param sig0init Default NULL. Initial var 
#' methylation level in unmethylated regions
#' @param sig1init Default NULL. Initial var 
#' methylation level in methylated regions
#' @param tauinit Default NULL. Initial var 
#' for measurement error
#' @param demo TRUE/FALSE. Should the function 
#' be used in demo mode to shorten examples in 
#' package. Defaults to FALSE. 
#' 
#' @return A object of the class \code{estimatecc} that 
#' contains information about the cell composition 
#' estimation (in the \code{summary} slot) and 
#' the cell composition estimates themselves 
#' (in the \code{cell_counts} slot).
#' 
#' @aliases estimatecc_custom
#' 
#' @docType methods
#' @name estimatecc_custom
#' @importFrom quadprog solve.QP
#'
#' @export
#' 
#' @examples
#' # This is a reduced version of the FlowSorted.Blood.450k 
#' # dataset available by using BiocManager::install("FlowSorted.Blood.450k),
#' # but for purposes of the example, we use the smaller version 
#' # and we set \code{demo=TRUE}. For any case outside of this example for 
#' # the package, you should set \code{demo=FALSE} (the default). 
#' 
#' dir <- system.file("data", package="methylCC")
#' files <- file.path(dir, "FlowSorted.Blood.450k.sub.RData") 
#' if(file.exists(files)){
#'     load(file = files)
#' 
#'     set.seed(12345)
#'     est <- estimatecc(object = FlowSorted.Blood.450k.sub, demo = TRUE) 
#'     cell_counts(est)
#'  }   
#' 
estimatecc_custom <- function(object, 
                              find_dmrs_object = NULL, 
                              verbose = TRUE, 
                              epsilon = 0.01, max_iter = 100, 
                              take_intersection = FALSE,
                              include_cpgs = FALSE, include_dmrs = TRUE,
                              init_param_method = "random", a0init = NULL,
                              a1init = NULL, sig0init = NULL, sig1init = NULL, 
                              tauinit = NULL)
{

  if(!(is(object, "RGChannelSet") || is(object, "GenomicMethylSet") || 
       is(object, "BSseq") || is(object, "GenomicRatioSet") )){
  stop("The object must be a RGChannelSet, GenomicMethylSet, BSseq or GenomicRatioSet object'.")
  }
  
  if(!(init_param_method %in% c("random", "known_regions")) ){
    stop("The init_param_method must be set to 'random' or 'known_regions'.")
  }
  
  if(is.null(find_dmrs_object)){
    if(!take_intersection){
      dmrs_found <- suppressWarnings(.find_dmrs(verbose = verbose, 
                                                include_cpgs = include_cpgs, 
                                                include_dmrs = include_dmrs))
    } else {
      eout <- .extract_raw_data(object)
      dmrs_found <- suppressWarnings(.find_dmrs(verbose = verbose, 
                                                gr_target=eout$gr_object, 
                                                include_cpgs = include_cpgs, 
                                                include_dmrs = include_dmrs))
      rm(eout)
    }    
      celltype_specific_dmrs <- granges(dmrs_found$regions_all)
      mcols(celltype_specific_dmrs) <- dmrs_found$zmat
  }
  
  if(!is.null(find_dmrs_object)){
      if(verbose){
        message("[estimatecc] Using regions in the find_dmrs_object argument.")
      }
      celltype_specific_dmrs <- granges(find_dmrs_object$regions_all)
      mcols(celltype_specific_dmrs) <- find_dmrs_object$zmat
  }
  
  dat <- .preprocess_estimatecc(object, verbose=verbose,
                      init_param_method=init_param_method, 
                      celltype_specific_dmrs = celltype_specific_dmrs)
  ymat <- as.matrix(dat$ymat)
  n <- dat$n
  ids <- dat$ids
  zmat <- dat$zmat
  K = ncol(zmat)
  R = nrow(zmat)
  
  if(init_param_method == "known_regions"){
    a0init = dat$a0init; sig0init = dat$sig0init
    a1init = dat$a1init; sig1init = dat$sig1init
  }
  
  # set up objects
  cell_counts  <- data.frame(array(NA, dim=c(n,K)))
  nregions_final = array(NA, dim = n)                
  samples_with_na <- apply(ymat, 2, function(x) { any(is.na(x)) })
  
  ## Include verbose messages about parameter estimation
  if(verbose){
    mes <- "[estimatecc] Starting parameter estimation using %s regions."
    message(sprintf(mes, R))
  }
  
  if(any(samples_with_na)){
    
    # samples with NAs in rows         
    for(ii in which(samples_with_na)){
      keep_rows <- c(!is.na(ymat[,ii]))
      ymat_sub <- t(t(ymat[keep_rows,ii]))
      zmat_sub <- zmat[keep_rows,]
      nregions_final[ii] <- sum(keep_rows)
      
      # Initialize MLEs
      init_step <- 
        .initializeMLEs(init_param_method = init_param_method,
                        n = n, K = K, 
                        Ys = ymat_sub, Zs = zmat_sub, 
                        a0init = a0init, a1init = a1init, 
                        sig0init = sig0init, sig1init = sig1init, 
                        tauinit = tauinit)
      
      # Run EM algorithm
      finalMLEs <- 
        .methylcc_engine(Ys = ymat_sub, Zs = zmat_sub,
                          current_pi_mle = init_step$init_pi_mle,
                          current_theta = init_step$init_theta,
                          epsilon=epsilon, max_iter = max_iter)
      
      cell_counts[ii,] <- as.data.frame(finalMLEs$pi_mle)
     }
  } 
  
  if(any(!samples_with_na)){
    
    ymat_sub <- as.matrix(ymat[, !samples_with_na])
    cut_samples <- factor(cut(seq_len(ncol(ymat_sub)),
                        breaks = unique(c(seq(0, ncol(ymat_sub), by = 100), 
                                          ncol(ymat_sub)))))
    
    final_mles <- NULL
    for(ind in seq_len(length(levels(cut_samples)))){
      keep_inds <- (cut_samples == levels(cut_samples)[ind])
      
      init_step <- try(
        .initializeMLEs(init_param_method = init_param_method,
                        n = n, K = K, 
                        Ys = as.matrix(ymat_sub[, keep_inds]), Zs = zmat, 
                        a0init = a0init, a1init = a1init, 
                        sig0init = sig0init, sig1init = sig1init, 
                        tauinit = tauinit), silent = TRUE)
      if(is(init_step, "try-error")){
    message(      
  "[estimatecc] There are not a sufficient number of differentially 
  methylated regions (DMRs) for cell composition estimation. Try 
  including both differntially methylated CpGs and DMRs by modifying 
  the estimatecc(include_cpgs=TRUE, include_dmrs=TRUE) function.")
  stop("Exiting the estimation now.")
      }

      # Run EM algorithm
      finalMLEs <- 
        .methylcc_engine(Ys = as.matrix(ymat_sub[, keep_inds]), Zs = zmat,
                         current_pi_mle = init_step$init_pi_mle,
                         current_theta = init_step$init_theta,
                         epsilon=epsilon, max_iter = max_iter)
      final_mles <- rbind(final_mles, finalMLEs$pi_mle)
    }
    
    # recored results
    cell_counts[!samples_with_na,] <- as.data.frame(final_mles)
    nregions_final[!samples_with_na] <- rep(R, sum(!samples_with_na))
  }
  
  if(verbose){
    mes <- "[estimatecc] Parameter estimation complete."
    message(sprintf(mes))
  }
  
  
  results <- new("estimatecc")
  colnames(cell_counts) <- ids
  rownames(cell_counts) <- colnames(ymat)
  results@cell_counts <- cell_counts
  results@summary <- list("class" = class(object),
                          "n_samples" = n, "celltypes" = ids,
                          "sample_names" = colnames(ymat),
                          "init_param_method" = init_param_method,
                          "n_regions" = nregions_final)


  return(results)
}
