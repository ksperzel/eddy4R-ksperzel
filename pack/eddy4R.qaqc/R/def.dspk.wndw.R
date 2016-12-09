##############################################################################################
#' @title Determine spike locations using window-based statistics

#' @author 
#' Stefan Metzger \email{eddy4R.info@gmail.com} \cr
#' Cove Sturtevant \email{csturtevant@neoninc.org}

#' @description 
#' Function definition. Determines spike locations based on window-based Gaussian statistics (arithmetic mean and standard deviation) and distribution statistics (median, median absolute deviation).

#' @param \code{data} Required input. A data frame or matrix containing the data to be evaluated.
#' @param \code{Trt} Optional. A list of the following parameters specifying the details of the despike algorithm. \cr
#' \code{AlgClss}: string. de-spiking algorithm class ["mean" or "median"] \cr
#' \code{NumPtsWndw}: integer. window size [data points] (must be odd for median / mad) \cr
#' \code{NumPtsSlid}: integer. window sliding increment [data points] \cr
#' \code{ThshStd}: number. threshold for detecting data point as spike [sigma / MAD_sigma] \cr
#' \code{NaFracMax}: The maximum allowable proportion of NA values per window in which spikes can be reliably determined \cr
#' \code{Infl}: number. inflation per iteration [fraction of sigma / MAD_sigma] \cr
#' \code{IterMax}: number or Inf. maximum number of iterations \cr
#' \code{NumPtsGrp}. integer. minimum group size that is not considered as consecutive spikes [data points] \cr
#' \code{NaTrt}. string. spike handling among iterations ["approx" or "omit"]
#' @param \code{Cntl} Optional. A list of the following parameters specifying other implementation details \cr
#' \code{NaOmit}: Logical. delete leading / trailing NAs from dataset? \cr
#' \code{Prnt}: Logical. print results? \cr
#' \code{Plot}: Logical. plot results?
#' @param \code{Vrbs} Optional. Option to output the quality flags (same size as \code{data}) rather than vector positions of failed and na values. Default = FALSE
  
#' @return A list of the following: \cr
#' \code{data}: the despiked data matrix \cr
#' \code{smmy}: a summary of the despike algorithm results, including iterations (\code{iter}), determined spikes (\code{news}), and total resultant NAs (\code{alls}) \cr
#' And one of the following:
#' \code{posSpk}: output if \code{Vrbs} is FALSE. A list of each input variable, with nested lists of $posQfSpk$fail and $posQfSpk$na vector positions of determined spikes and 'cannot evaluate' positions, respectively. This output format is identical to def.plau
#' \code{qfSpk}: output if \code{Vrbs} is TRUE. A data frame the same size as data with the quality flag values [-1,0,1] for each input variable

#' @references
#' Hojstrup, J.: A statistical data screening procedure, Meas. Sci. Technol., 4, 153-157, doi:10.1088/0957-0233/4/2/003, 1993. \cr
#' Metzger, S., Junkermann, W., Mauder, M., Beyrich, F., Butterbach-Bahl, K., Schmid, H. P., and Foken, T.: Eddy-covariance flux measurements with a weight-shift microlight aircraft, Atmos. Meas. Tech., 5, 1699-1717, doi:10.5194/amt-5-1699-2012, 2012. \cr
#' Vickers, D., and Mahrt, L.: Quality control and flux sampling problems for tower and aircraft data, J. Atmos. Oceanic Technol., 14, 512-526, doi:10.1175/1520-0426(1997)014<0512:QCAFSP>2.0.CO;2, 1997. \cr

#' @keywords spike, de-spiking

#' @examples Currently none

#' @seealso Currently none

#' @export

# changelog and author contributions / copyrights
#   Stefan Metzger (2014-09-08)
#     original creation
#   Stefan Metzger (2015-06-17)
#     added parameters "slide", "inflate", "iter_max", "na.Trt"
#   Stefan Metzger (2015-12-07)
#     added Roxygen2 tags
#   Cove Sturtevant (2015-12-15)
#     fixed bug in omitting leading/trailing na
#   Cove Sturtevant (2016-01-07)
#     adjusted naming throughout to conform to EC TES coding convention, and added documentation
#   Cove Sturtevant (2016-01-08)
#     changed output vector of spike locations to be a list of failed and na (unable to eval) locations
#     also added an input parameter NaFracMax specifying the maximum proportion of NA values in a window 
#     for reliable spike estimation. 
#   Cove Sturtevant (2016-02-09)
#     added loading of required library eddy4R.base
#   Cove Sturtevant (2016-11-9)
#     added verbose option for reporting quality flag values [-1,0,1] as opposed to vector positions 
#        of failed and na values
#     adjusted output of vector positions of failed and na spike positions (Vrbs = FALSE) to be nested 
#        under each variable rather than each variable nested under the lists of failed and na results 
##############################################################################################


def.dspk.wndw <- function (
  data,
  Trt=list(
    AlgClss=c("mean", "median")[2],   #de-spiking algorithm class [mean vs. median]
    NumPtsWndw=c(11, 101)[2],           #window size [data points] (must be odd for median / mad); mean:10, med:101
    NumPtsSlid=1,                        #window sliding increment [data points]
    ThshStd=c(3.5, 20)[2],           #threshold for detecting data point as spike [sigma / MAD_sigma]; mean:3.5, med:20
    NaFracMax = 0.1,              # maximum proportion of NAs allowable within a window for reliable spike determination
    Infl=0,                      #inflation per iteration [fraction of sigma / MAD_sigma]
    IterMax=Inf,                   #maximum number of iterations [-]
    NumPtsGrp=c(4, 10)[2],              #minimum group size that is not considered as consecutive spikes [data points]; mean:4, med:10
    NaTrt=c("approx", "omit")[2] #spike handling among iterations ["approx" or "omit"]
  ),
  Cntl=list(
    NaOmit=c(TRUE, FALSE)[2],      #delete leading / trailing NAs from dataset?
    Prnt=c(TRUE, FALSE)[1],        #print results?
    Plot=c(TRUE, FALSE)[1]          #plot results?
  ),
  Vrbs=FALSE # output vector positions of failed and na test values (Vrbs=FALSE), or quality flag values [-1,0,1] (Vrbs=TRUE)
) {

  if (!require(eddy4R.base)) {
    stop("Please install package 'eddy4R.base' before continuing")
  }
  
  #data always as matrix
  mat <- as.matrix(data)
  numVar <- base::ncol(mat)
  
  # Initialize output of actual flag values when using verbose option
  if(Vrbs){
    qfSpk <- data
    qfSpk[] <- 0    
  }


  ###
  #start loop around data columns
  posSpk <- base::vector("list",numVar) # Initialize output of spike positions for each variable
  names(posSpk) <- names(data)
  for(idxVar in 1:numVar) {
    #idxVar<-1
    trns <- mat[,idxVar]
    
    # initialize fail and na spike positions for this variable
    posSpk[[idxVar]] <- list(posQfSpk=list(fail=numeric(0),na=numeric(0)))
    
    # Store na positions as "unable to evaluate" spikes
    posSpk[[idxVar]]$posQfSpk$na <- which(is.na(trns))
    
    if(Trt$NaTrt == "approx") {
      trns <- approx(x=index(trns), y=trns, xout=index(trns))$y
    }
    
    posNa <- which(is.na(trns))
    iter <- 0
    posSpkPrlm <- integer(0)
    ###
  
  
    ###
    #start loop around window sizes
    for(idxNumPtsWndw in 1:length(Trt$NumPtsWndw)) {
      #idxNumPtsWndw<-1
      numPtsWndw <- Trt$NumPtsWndw[idxNumPtsWndw]
      numSpkNew <- 1
  
  
      while(numSpkNew != 0) {
        iter <- iter + 1
  
        #apply spike detection over windows
        	if(Trt$AlgClss == "mean") {
        	#mean and sd (> 1 s per 1e4 entries)
        	  #location - rolling mean (representing center of data)
        	    if(all(!is.na(trns)) & Trt$NumPtsSlid == 1) {
        	      cntrRoll <- zoo::rollmean(x=zoo::zoo(trns), k=numPtsWndw, fill = NA, align="center")
        	    } else {
        	      cntrRoll <- zoo::rollapply(data=zoo::zoo(trns), width=numPtsWndw, FUN=mean, by=Trt$NumPtsSlid, na.rm=TRUE, fill = NA)
        	    }
        	  #scale (spread of data)
        	    sprdRoll <- zoo::rollapply(data=zoo::zoo(trns), width=numPtsWndw, FUN=sd, by=Trt$NumPtsSlid, na.rm=TRUE, fill = NA)
        	
    	    } else {
        	#median and mad (> 2 s per 1e4 entries)
        	  #location
        	    if(all(!is.na(trns)) & Trt$NumPtsSlid == 1) {
        	      cntrRoll <- zoo::rollmedian(x=zoo::zoo(trns), k=numPtsWndw, fill = NA, align="center")
        	    } else {
        	      cntrRoll <- zoo::rollapply(data=zoo::zoo(trns), width=numPtsWndw, FUN=median, by=Trt$NumPtsSlid, na.rm=TRUE, fill = NA)
        	    }
        	  #scale
        	    sprdRoll <- zoo::rollapply(data=zoo::zoo(trns), width=numPtsWndw, FUN=mad, by=Trt$NumPtsSlid, na.rm=TRUE, fill = NA) * (numPtsWndw / (numPtsWndw - 0.8))
        	}
      
        # Find windows where there were not enough data points to reliably compute statistics
        naFracRoll <- zoo::rollapply(data=zoo::zoo(trns),width=numPtsWndw,FUN=function(Var){length(which(is.na(Var)))/length(Var)},by=Trt$NumPtsSlid, fill = NA)
        posNaSpkNew <- which(naFracRoll > Trt$NaFracMax)
        
        #calculate and match criteria
          crit <- abs((trns - cntrRoll) / sprdRoll)
        	posSpkNew <- which(crit > (Trt$ThshStd * (1 + (iter - 1) * Trt$Infl)))
        	posNaSpkNew <- intersect(posSpkNew,posNaSpkNew) # record spike positions in which there were too many NAs in the window
        	posSpkNew <- setdiff(posSpkNew,posNaSpkNew) # remove unreliable spikes
        	numSpkNew <- length(posSpkNew)
        
        #replicate cntrRoll and sprdRoll for untreated indices if sliding increment > 1
          if(Trt$NumPtsSlid > 1) {
            
            posUntr <- which(!is.na(cntrRoll))
            posUntrBgn <- sapply(posUntr, function(val) val - (Trt$NumPtsWndw/2 - 1))
            posUntrEnd <- sapply(posUntr, function(val) val + (Trt$NumPtsWndw/2))
            
            #assign local variables
              cntrRollLocl <- cntrRoll
              sprdRollLocl <- sprdRoll
              naFracRollLocl <- naFracRoll
  
            #forward
              #assignment
                for(idxUntr in 1:length(posUntr)){
                #idxUntr <- 1
                
                  cntrRollLocl[posUntrBgn[idxUntr]:posUntrEnd[idxUntr]] <- cntrRoll[posUntr[idxUntr]]
                  sprdRollLocl[posUntrBgn[idxUntr]:posUntrEnd[idxUntr]] <- sprdRoll[posUntr[idxUntr]]
                  naFracRollLocl[posUntrBgn[idxUntr]:posUntrEnd[idxUntr]] <- naFracRoll[posUntr[idxUntr]]
                  
                }; rm(idxUntr)
              
              #calculate and match criteria
                crit <- abs((trns - cntrRollLocl) / sprdRollLocl)
                posNaSpkNewFwd <- which(naFracRollLocl > Trt$NaFracMax)

                posSpkNewFwd <- which(crit > (Trt$ThshStd * (1 + (iter - 1) * Trt$Infl)))
                posNaSpkNewFwd <- intersect(posSpkNewFwd,posNaSpkNewFwd) # record spike positions in which there were too many NAs in the window
                posSpkNewFwd <- setdiff(posSpkNewFwd,posNaSpkNewFwd) # remove unreliable spikes

            #backward
              #assignment
                for(idxUntr in length(posUntr):1){
                #idxUntr <- 1
                
                  cntrRollLocl[posUntrBgn[idxUntr]:posUntrEnd[idxUntr]] <- cntrRoll[posUntr[idxUntr]]
                  sprdRollLocl[posUntrBgn[idxUntr]:posUntrEnd[idxUntr]] <- sprdRoll[posUntr[idxUntr]]
                  naFracRollLocl[posUntrBgn[idxUntr]:posUntrEnd[idxUntr]] <- naFracRoll[posUntr[idxUntr]]
                  
                }; rm(idxUntr)
              
              #calculate and match criteria
                crit <- abs((trns - cntrRollLocl) / sprdRollLocl)
                posNaSpkNewBwd <- which(naFracRollLocl > Trt$NaFracMax)

                posSpkNewBwd <- which(crit > (Trt$ThshStd * (1 + (iter - 1) * Trt$Infl)))
                posNaSpkNewBwd <- intersect(posSpkNewBwd,posNaSpkNewBwd) # record spike positions in which there were too many NAs in the window
                posSpkNewBwd <- setdiff(posSpkNewBwd,posNaSpkNewBwd) # remove unreliable spikes
                
                  
            #combine results
              posSpkNew <- unique(c(posSpkNewFwd, posSpkNewBwd))
              posNaSpkNew <- unique(c(posNaSpkNewFwd, posNaSpkNewBwd))
              numSpkNew <- length(posSpkNew)
       
          #clean up
            rm(posUntrEnd, cntrRollLocl, posUntr, sprdRollLocl, posUntrBgn, posSpkNewFwd, posSpkNewBwd)
          
          }
      
      
        #remove spikes and store results
          if(numSpkNew > 0) {
            
            #remove spikes
              trns[posSpkNew] <- NA
              
            #store results
              if(iter == 1) {
                
                posSpkPrlm <- posSpkNew
                
              } else {
                
                posSpkPrlm <- base:::sort(unique(c(posSpkPrlm, posSpkNew)))
                
              }
              posSpk[[idxVar]]$posQfSpk$na <- base:::sort(unique(c(posSpk[[idxVar]]$posQfSpk$na,posNaSpkNew)))
            
          }
  
        #plotting
        	if(Cntl$Plot == TRUE) {
        	  plot(log10(crit), type="p", ylim=c(-10,10), main=paste(dimnames(mat)[[2]][idxVar], ", step ", iter, ", window ", numPtsWndw, sep=""))
        	  abline(h=log10(Trt$ThshStd * (1 + (iter - 1) * Trt$Infl)))
        	}
  
        #how many iterations do we need?
        	if(Cntl$Prnt == TRUE) {
        	  print(paste("Variable ", idxVar, " of ", numVar, ", iteration ", iter, " is finished. ", 
                        numSpkNew, " new spikes, totally ", length(posSpkPrlm), " spikes.", sep=""))
        	}
      
        #break if maximum number of iterations is reached
          if(iter == Trt$IterMax) break  
      
        #linearly interpolate values
          if(Trt$NaTrt == "approx") trns <- approx(x=index(trns), y=trns, xout=index(trns))$y
      
      
      }
  
  
    ###
    }
    #end loop around window sizes
    ###
  
  
  # #where have we found spikes
  #   posSpkPrlm <- which(is.na(trns))
  #   if(length(posNa) > 0 & length(posSpkPrlm) > 0) {
  #     whr_n <- sapply(1:length(posNa), function(val) which(posSpkPrlm == posNa[val]))
  #     posSpkPrlm <- posSpkPrlm[-whr_n]
  #   }
  
  
  #which of them are neighboring?
    if(is.logical(Trt$NumPtsGrp[1]) & Trt$NumPtsGrp[1] == FALSE) {
    #omit group considerations?
      nons <- integer(0); posNons <- integer(0)
      posSpkVar <- posSpkPrlm
    } else {
    #consider groups
      if(length(posSpkPrlm) > 0) {
      	diffIdx <- diff(posSpkPrlm)
      	idxNbr <- unique(c(posSpkPrlm[which(diffIdx == 1)], posSpkPrlm[which(diffIdx == 1)] + 1))
      	spkGrp <- rep(0, length(trns))
      	spkGrp[idxNbr] <- 1
        #are there groups of neighbors >= Trt$NumPtsGrp length flagged as spikes?
      	spkGrpMean <- zoo::rollmean(x=zoo::zoo(spkGrp), k=Trt$NumPtsGrp, fill = NA, align="center")
      	posSpkGrp <- which(spkGrpMean == 1)
      	if(length(posSpkGrp) > 0) {
      	    posSpkGrpWndw <- (1:Trt$NumPtsGrp) - ceiling(Trt$NumPtsGrp / 2)
      	    nons <- unique(sapply(1:length(posSpkGrp), function(val) posSpkGrp[val] + posSpkGrpWndw))
      	    posNons <- sapply(1:length(nons), function(val) which(posSpkPrlm == nons[val]))
      	    posSpkVar <- posSpkPrlm[-posNons]
      	} else {
      	    nons <- integer(0); posNons <- integer(0)
      	    posSpkVar <- posSpkPrlm
      	}
      } else {
        nons <- integer(0); posNons <- integer(0)
        posSpkVar <- integer(0)
      }
    }
  
  #store result
    posSpk[[idxVar]]$posQfSpk$fail <- posSpkVar
    mat[posSpkVar,idxVar] <- NA
    smmyOutVar <- as.matrix(c(iter, length(posSpkVar), length(which(is.na(mat[,idxVar])))))
    dimnames(smmyOutVar)[[1]] <- c("iter", "news", "alls")
    if(idxVar == 1) {
      smmyOut <- smmyOutVar
      } else {
      smmyOut <- cbind(smmyOut, smmyOutVar)
      }
  
  #how many iterations do we need?
    if(Cntl$Prnt == TRUE) {
      print(paste("Variable ", idxVar, " of ", numVar, " (", dimnames(mat)[[2]][idxVar], ") is finished after ", smmyOut[1,idxVar], " iteration(s). ",
                  smmyOut[2,idxVar], " spike(s) were detected, totally ", smmyOut[3,idxVar], " NAs.", sep=""))
    }
  
    # For Verbose option, output actual flag values
    if(Vrbs) {
      qfSpk[[idxVar]][posSpk[[idxVar]]$posQfSpk$na] <- -1 # flag na values
      qfSpk[[idxVar]][posSpkVar] <- 1 # flag failed values
    } 
    
  ###
  }
  #end loop around data columns
  dimnames(smmyOut)[[2]] <- dimnames(mat)[[2]]
  ###
  
  
  #make sure that there's no NAs in first and last row of all columns (for interpolation)
    if(Cntl$NaOmit == TRUE) {
      allVAL <- which(sapply(1:nrow(mat), function(x) all(!is.na(mat[x,]))) == TRUE)
      mat <- mat[(allVAL[1]:allVAL[length(allVAL)]),]
    }
  
  
  #return results
  # For Verbose option, output actual flag values, otherwise output vector positions of failed and na values
  if(Vrbs) {
    rpt <- list(
      data=mat,
      smmy=smmyOut,
      qfSpk=qfSpk
    )
  } else {
    rpt <- list(
      data=mat,
      smmy=smmyOut,
      posSpk=posSpk
    )
  }
    
    return(rpt)
  
  }