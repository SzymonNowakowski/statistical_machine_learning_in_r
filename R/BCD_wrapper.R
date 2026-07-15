# Load ClusterLearn shared library on startup
dyn.load('/opt/ClusterLearn/univariate/BCD_solver.so')

# Global wrapper function for ClusterLearn solver
BCD_wrapper_R <- function(X, y, Xval, y_val, numlevels, l0_list, l1_list, l2_list) {
  n <- as.integer(nrow(X))
  r <- as.integer(ncol(X))
  nval <- as.integer(nrow(Xval))
  
  x_vector <- as.integer(X)
  y_vector <- as.double(y)
  xval_vector <- as.integer(Xval)
  yval_vector <- as.double(y_val)
  
  l0 <- as.double(l0_list)
  l1 <- as.double(l1_list)
  l2 <- as.double(l2_list)
  
  nl0 <- as.integer(length(l0_list))
  nl1 <- as.integer(length(l1_list))
  nl2 <- as.integer(length(l2_list))
  
  numlevels <- as.integer(numlevels)
  p <- as.integer(sum(numlevels))
  
  beta0 <- double(p)
  beta <- double(p + 1)
  
  # Call the compiled C++ library directly
  out <- .C('BCD_solve',
            n, r, x_vector, y_vector, nval, xval_vector, yval_vector,
            l0, nl0, l1, nl1, l2, nl2, numlevels, beta0, beta = beta
  )
  return(out$beta)
}
