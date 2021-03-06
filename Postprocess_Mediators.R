##---------------------------------------------------------------
## Required libraries
##---------------------------------------------------------------

#----- Parallel computing
library(doParallel)

#----- Make clusters based on the number of CPU cores
cl<-makeCluster(64) # 64 cores
registerDoParallel(cl)
getDoParWorkers()

#----- Support parallel excution
library(foreach)



##---------------------------------------------------------------
## Extract MCMC samples from Stan outputs
##---------------------------------------------------------------

#----- Load MCMC samples and Data
load("Master.RData")
load("MCMCsamples.RData")

#------ Set Treatment (TRT), Outcome (OUT), Mediators (M) and Covariates (X)
Data <- Master
OUT <- Data$PM.2.5
TRT <- Data$SO2.SC
M <- cbind(Data$SO2_Annual, Data$NOx_Annual, Data$CO2_Annual)
X <- cbind(Data$S_n_CR, Data$NumNOxControls, Data$Heat_Input/100000, Data$Barometric_Pressure, Data$Temperature,  Data$PctCapacity, Data$sulfur_Content, Data$Phase2_Indicator, Data$Operating_Time/1000)


dim.cov <- dim(X)[2] #<--------- Num. of Covariates

#------ Variables by treatments
x0 <- X[which(TRT==0),]
x1 <- X[which(TRT==1),]

y0 <- OUT[which(TRT==0)]
y1 <- OUT[which(TRT==1)]

m0 <- log(M[which(TRT==0),])
m1 <- log(M[which(TRT==1),])

n0 <- dim(x0)[1]
n1 <- dim(x1)[1]


#----- Extract MCMC samples from each marginal distribution
data.y0 <- para.y0[,2:35]
data.y1 <- para.y1[,2:35]
data.m10 <- para.m10[,2:35]
data.m11 <- para.m11[,2:35]
data.m20 <- para.m20[,2:35]
data.m21 <- para.m21[,2:35]
data.m30 <- para.m30[,2:35]
data.m31 <- para.m31[,2:35]

COR <- para.C[,29:56]

#----- Parameters of the models under Z=1
gamma10 <- data.y1[,9:17]
gamma11 <- data.y1[,18:25]
w1 <- data.y1[,26:34]
beta1_10 <- data.m11[,9:17]
beta1_11 <- data.m11[,18:25]
beta2_10 <- data.m21[,9:17]
beta2_11 <- data.m21[,18:25]
beta3_10 <- data.m31[,9:17]
beta3_11 <- data.m31[,18:25]
s1_1 <- data.m11[,26:34]
s2_1 <- data.m21[,26:34]
s3_1 <- data.m31[,26:34]
psi1 <- data.y1[,1:8]
psi1_1 <- data.m11[,1:8]
psi2_1 <- data.m21[,1:8]
psi3_1 <- data.m31[,1:8]


#----- Parameters of the models under Z=0
gamma00 <- data.y0[,9:17]
gamma01 <- data.y0[,18:25]
w0 <- data.y0[,26:34]
beta1_00 <- data.m10[,9:17]
beta1_01 <- data.m10[,18:25]
beta2_00 <- data.m20[,9:17]
beta2_01 <- data.m20[,18:25]
beta3_00 <- data.m30[,9:17]
beta3_01 <- data.m30[,18:25]
s1_0 <- data.m10[,26:34]
s2_0 <- data.m20[,26:34]
s3_0 <- data.m30[,26:34]
psi0 <- data.y0[,1:8]
psi1_0 <- data.m10[,1:8]
psi2_0 <- data.m20[,1:8]
psi3_0 <- data.m30[,1:8]

#----- Setting Thinning and Burn-in's
Thin <- 5
Burn0 <- 90000  # Extra burn-in periods for Models under Z=0
Burn1 <- 90000   # Extra burn-in periods for Models under Z=1


#----- Set the number of post-processing steps, N
n.iter <- 2000

##---------------------------------------------------------------
## 'Main' function on each cluster (parallel)
##---------------------------------------------------------------


main <- function(temp){
  
  
  #----- Require multivariate normal distribuion on each cluster
  library(mnormt)
  
  #----- Index of iterations (on parallel)
  j <- temp
  
  #----- The number of covariates samples (with replacement) for the empirical distribution
  size <- 5000
  s.covariate <- data.frame(X[sample(seq(1,dim(X)[1]), size = size, replace = TRUE),])  #----- Covariates samples
  
  #----- Index of posterior samples
  index0 <- Thin * j + Burn0; index1 <- Thin * j + Burn1
  
  #----- Construct the correlation matrix
  Cor01 <- matrix(c(1, COR[index0,c(8,9,11,12,13,8)],1,COR[index0,c(14,16,17,18,9,14)],1,COR[index0,c(20,21,22,11,16,20)],1,COR[index0,c(26,27,12,17,21,26)],1,COR[index0,c(28,13,18,22,27,28)],1),6,6,byrow=TRUE)
  
  #----- mixing parameters
  ppi.m10 <- pmax(psi1_0[index0,], 0)
  ppi.m20 <- pmax(psi2_0[index0,], 0)
  ppi.m30 <- pmax(psi3_0[index0,], 0)
  ppi.m11 <- pmax(psi1_1[index1,], 0)
  ppi.m21 <- pmax(psi2_1[index1,], 0)
  ppi.m31 <- pmax(psi3_1[index1,], 0)
  
  pi.m10 <- NULL
  pi.m10[1] <- ppi.m10[1]
  pi.m10[2:8] <- sapply(2:8, function(i) ppi.m10[i] * prod(1 - ppi.m10[1:(i-1)]))
  pi.m10[9] <- prod(1-ppi.m10[1:8])

  pi.m20 <- NULL
  pi.m20[1] <- ppi.m20[1]
  pi.m20[2:8] <- sapply(2:8, function(i) ppi.m20[i] * prod(1 - ppi.m20[1:(i-1)]))
  pi.m20[9] <- prod(1-ppi.m20[1:8])

  pi.m30 <- NULL
  pi.m30[1] <- ppi.m30[1]
  pi.m30[2:8] <- sapply(2:8, function(i) ppi.m30[i] * prod(1 - ppi.m30[1:(i-1)]))
  pi.m30[9] <- prod(1-ppi.m30[1:8])

  pi.m11 <- NULL
  pi.m11[1] <- ppi.m11[1]
  pi.m11[2:8] <- sapply(2:8, function(i) ppi.m11[i] * prod(1 - ppi.m11[1:(i-1)]))
  pi.m11[9] <- prod(1-ppi.m11[1:8])

  pi.m21 <- NULL
  pi.m21[1] <- ppi.m21[1]
  pi.m21[2:8] <- sapply(2:8, function(i) ppi.m21[i] * prod(1 - ppi.m21[1:(i-1)]))
  pi.m21[9] <- prod(1-ppi.m21[1:8])

  pi.m31 <- NULL
  pi.m31[1] <- ppi.m31[1]
  pi.m31[2:8] <- sapply(2:8, function(i) ppi.m31[i] * prod(1 - ppi.m31[1:(i-1)]))
  pi.m31[9] <- prod(1-ppi.m31[1:8])


  #---- Sampling mediators conditional on covariates
  M0M1 <- function(k){
      
    F <- pnorm(rmnorm(1, mean=rep(0,6), Cor01),0,1)
    X.temp <- s.covariate[k,]
    for(i in 1:3){
      for(k in 0:1){
        eval(parse(text=paste("clus.m",i,k," <- which(rmultinom(1, 1, pi.m",i,k,")==1)", sep="")))
      }
    }
    
    s.m10<-qnorm(F[4], mean = beta1_00[index0,clus.m10] + beta1_01[index0,]%*%t(X.temp), sd = sqrt(s1_0[index0,clus.m10]))
    s.m20<-qnorm(F[5], mean = beta2_00[index0,clus.m20] + beta2_01[index0,]%*%t(X.temp), sd = sqrt(s2_0[index0,clus.m20]))
    s.m30<-qnorm(F[6], mean = beta3_00[index0,clus.m30] + beta3_01[index0,]%*%t(X.temp), sd = sqrt(s3_0[index0,clus.m30]))
    
    s.m11<-qnorm(F[1], mean = beta1_10[index1,clus.m11] + beta1_11[index1,]%*%t(X.temp), sd = sqrt(s1_1[index1,clus.m11]))
    s.m21<-qnorm(F[2], mean = beta2_10[index1,clus.m21] + beta2_11[index1,]%*%t(X.temp), sd = sqrt(s2_1[index1,clus.m21]))
    s.m31<-qnorm(F[3], mean = beta3_10[index1,clus.m31] + beta3_11[index1,]%*%t(X.temp), sd = sqrt(s3_1[index1,clus.m31]))
    
    return(c(s.m10,s.m20,s.m30,s.m11,s.m21,s.m31))
  }
  
  C.sample <- sapply(seq(1,size, by=1), function(x) M0M1(x))
  
  
  M1 <- C.sample[4,] - C.sample[1,] # Causal effect on the 1st mediator
  M2 <- C.sample[5,] - C.sample[2,] # Causal effect on the 2nd mediator
  M3 <- C.sample[6,] - C.sample[3,] # Causal effect on the 3rd mediator
  
  # tM1 <- exp(mean(C.sample[4,])) - exp(mean(C.sample[1,])) # Causal effect on the 1st mediator (original scale)
  # tM2 <- exp(mean(C.sample[5,])) - exp(mean(C.sample[2,])) # Causal effect on the 2nd mediator (original scale)
  # tM3 <- exp(mean(C.sample[6,])) - exp(mean(C.sample[3,])) # Causal effect on the 3rd mediator (original scale)


  return(rbind(M1,M2,M3))
}

result<-foreach(temp = 1:n.iter, .combine = rbind) %dopar% main(temp)

save(result, file="result_Mediators.RData")
stopCluster(cl)


