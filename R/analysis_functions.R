#' Bi-partite network analysis tools
#'
#' This function analyzes a bi-partite network.
#'
#' @param network.1 starting network, a genes by transcription factors data.frame with scores 
#' for the existence of edges between
#' @param network.2 final network, a genes by transcription factors data.frame with scores 
#' for the existence of edges between
#' @param by.tfs logical indicating a transcription factor based transformation.    If 
#' false, gives gene by gene transformation matrix
#' @param remove.diagonal logical for returning a result containing 0s across the diagonal
#' @param standardize logical indicating whether to standardize the rows and columns
#' @param method character specifying which algorithm to use, default='ols'
#' @return matrix object corresponding to transition matrix
#' @import MASS
#' @importFrom penalized optL1
#' @importFrom reshape2 melt
#' @export
#' @examples
#' data(yeast)
#' cc.net.1 <- monsterNI(yeast$motif,yeast$exp.cc[1:1000,1:20])
#' cc.net.2 <- monsterNI(yeast$motif,yeast$exp.cc[1:1000,31:50])
#' transformation.matrix(cc.net.1, cc.net.2)
transformation.matrix <- function(network.1, network.2, by.tfs=TRUE, standardize=FALSE, 
                                remove.diagonal=TRUE, method="ols"){
    if(is.list(network.1)&&is.list(network.2)){
        if(by.tfs){
            net1 <- t(network.1$reg.net)
            net2 <- t(network.2$reg.net)
        } else {
            net1 <- network.1$reg.net
            net2 <- network.2$reg.net
        }
    } else if(is.matrix(network.1)&&is.matrix(network.2)){
        if(by.tfs){
            net1 <- t(network.1)
            net2 <- t(network.2)
        } else {
            net1 <- network.1
            net2 <- network.2
        }
    } else {
        stop("Networks must be lists or matrices")
    }
    
    if(!method%in%c("ols","kabsch","L1","orig")){
        stop("Invalid method.  Must be one of 'ols', 'kabsch', 'L1','orig'")
    }
    if (method == "kabsch"){
        tf.trans.matrix <- kabsch(net1,net2)
    }
    if (method == "orig"){
        svd.net2 <- svd(net2)
        tf.trans.matrix <- svd.net2$v %*% diag(1/svd.net2$d) %*% t(svd.net2$u) %*% net1
    }
    if (method == "ols"){
        net2.star <- sapply(1:ncol(net1), function(i,x,y){
            lm(y[,i]~x[,i])$resid
        }, net1, net2)
        tf.trans.matrix <- ginv(t(net1)%*%net1)%*%t(net1)%*%net2.star
        colnames(tf.trans.matrix) <- colnames(net1)
        rownames(tf.trans.matrix) <- colnames(net1)
        print("Using OLS method")

    }
    if (method == "L1"){
        net2.star <- sapply(1:ncol(net1), function(i,x,y){
                lm(y[,i]~x[,i])$resid
        }, net1, net2)
        tf.trans.matrix <- sapply(1:ncol(net1), function(i){
                z <- optL1(net2.star[,i], net1, fold=5, minlambda1=1, 
                        maxlambda1=2, model="linear", standardize=TRUE)
                coefficients(z$fullfit, "penalized")
        })
        colnames(tf.trans.matrix) <- rownames(tf.trans.matrix)
        print("Using L1 method")

    }
    if (standardize){
        tf.trans.matrix <- apply(tf.trans.matrix, 1, function(x){
            x/sum(abs(x))
        })
    }

    if (remove.diagonal){
        diag(tf.trans.matrix) <- 0
    }
    colnames(tf.trans.matrix) <- rownames(tf.trans.matrix)
    tf.trans.matrix
}

kabsch <- function(P,Q){

    P <- apply(P,2,function(x){
        x - mean(x)
    })
    Q <- apply(Q,2,function(x){
        x - mean(x)
    })
    covmat <- cov(P,Q)
    P.bar <- colMeans(P)
    Q.bar <- colMeans(Q)
    num.TFs <- ncol(P)        #n
    num.genes <- nrow(P)    #m

    #     covmat <- (t(P)%*%Q - P.bar%*%t(Q.bar)*(num.genes))

    svd.res <- svd(covmat-num.TFs*Q.bar%*%t(P.bar))

    # Note the scalar multiplier in the middle.
    # NOT A MISTAKE!
    c.k <- colSums(P %*% svd.res$v * Q %*% svd.res$u) - 
        num.genes*(P.bar%*%svd.res$v)*(Q.bar%*%svd.res$u)

    E <- diag(c(sign(c.k)))

    W <- svd.res$v %*% E %*% t(svd.res$u)
    rownames(W) <- colnames(P)
    colnames(W) <- colnames(P)
    W
}


#' Transformation matrix plot
#'
#' This function plots a hierachically clustered heatmap and 
#' corresponding dendrogram of a transaction matrix
#'
#' @param monsterObj monsterAnalysis Object
#' @param method distance metric for hierarchical clustering.    
#' Default is "Pearson correlation"
#' @export
#' @import ggplot2
#' @import grid
#' @import stats
#' @return ggplot2 object for transition matrix heatmap
#' @examples
#' # data(yeast)
#' # design <- c(rep(0,20),rep(NA,10),rep(1,20))
#' # monsterRes <- monster(yeast$exp.cc, design, yeast$motif, nullPerms=100, numMaxCores=4)
#' data(monsterRes)
#' hcl.heatmap.plot(monsterRes)
hcl.heatmap.plot <- function(monsterObj, method="pearson"){
    x <- monsterObj@tm
    if(method=="pearson"){
        dist.func <- function(y) as.dist(cor(y))
    } else {
        dist.func <- dist
    }
    x <- scale(x)
    dd.col <- as.dendrogram(hclust(dist.func(x)))
    col.ord <- order.dendrogram(dd.col)

    dd.row <- as.dendrogram(hclust(dist.func(t(x))))
    row.ord <- order.dendrogram(dd.row)

    xx <- x[col.ord, row.ord]
    xx_names <- attr(xx, "dimnames")
    df <- as.data.frame(xx)
    colnames(df) <- xx_names[[2]]
    df$Var1 <- xx_names[[1]]
    df$Var1 <- with(df, factor(Var1, levels=Var1, ordered=TRUE))
    mdf <- melt(df)


    ddata_x <- dendro_data(dd.row)
    ddata_y <- dendro_data(dd.col)

    ### Set up a blank theme
    theme_none <- theme(
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        panel.background = element_blank(),
        axis.title.x = element_text(colour=NA),
        axis.title.y = element_blank(),
        axis.text.x = element_blank(),
        axis.text.y = element_blank(),
        axis.line = element_blank()
    )
    ### Set up a blank theme
    theme_heatmap <- theme(
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        panel.background = element_blank(),
        axis.title.x = element_text(colour=NA),
        axis.title.y = element_blank(),
        axis.text.x = element_blank(),
        axis.text.y = element_blank(),
        axis.line = element_blank()
    )
    ### Create plot components ###
    # Heatmap
    p1 <- ggplot(mdf, aes(x=variable, y=Var1)) +
        geom_tile(aes(fill=value)) + 
        scale_fill_gradient2() + 
        theme(axis.text.x = element_text(angle = 90, hjust = 1))

    # Dendrogram 1
    p2 <- ggplot(segment(ddata_x)) +
        geom_segment(aes(x=x, y=y, xend=xend, yend=yend)) +
        theme_none + theme(axis.title.x=element_blank())

    # Dendrogram 2
    p3 <- ggplot(segment(ddata_y)) +
        geom_segment(aes(x=x, y=y, xend=xend, yend=yend)) +
        coord_flip() + theme_none

    ### Draw graphic ###

    grid.newpage()
    print(p1, vp=viewport(0.80, 0.8, x=0.400, y=0.40))
    print(p2, vp=viewport(0.73, 0.2, x=0.395, y=0.90))
    print(p3, vp=viewport(0.20, 0.8, x=0.910, y=0.43))
}

#' Principal Components plot of transformation matrix
#'
#' This function plots the first two principal components for a 
#' transaction matrix
#'
#' @param monsterObj a monsterAnalysis object resulting from a monster analysis
#' @param title The title of the plot
#' @param clusters A vector indicating the number of clusters to compute
#' @param alpha A vector indicating the level of transparency to be plotted
#' @return ggplot2 object for transition matrix PCA
#' @import ggdendro
#' @export
#' @examples
#' # data(yeast)
#' # design <- c(rep(0,20),rep(NA,10),rep(1,20))
#' # monsterRes <- monster(yeast$exp.cc, design, yeast$motif, nullPerms=100, numMaxCores=4)#' 
#' data(monsterRes)
#' # Color the nodes according to cluster membership
#' clusters <- kmeans(slot(monsterRes, 'tm'),3)$cluster 
#' transitionPCAPlot(monsterRes, 
#' title="PCA Plot of Transition - Cell Cycle vs Stress Response", 
#' clusters=clusters)
transitionPCAPlot <-    function(monsterObj, 
                                title="PCA Plot of Transition", 
                                clusters=1, alpha=1){
    tm.pca <- princomp(monsterObj@tm)
    odsm <- apply(monsterObj@tm,2,function(x){t(x)%*%x})
    odsm.scaled <- 2*(odsm-mean(odsm))/sd(odsm)+4
    scores.pca <- as.data.frame(tm.pca$scores)
    scores.pca <- cbind(scores.pca,'node.names'=rownames(scores.pca))
    ggplot(data = scores.pca, aes(x = Comp.1, y = Comp.2, label = node.names)) +
        geom_hline(yintercept = 0, colour = "gray65") +
        geom_vline(xintercept = 0, colour = "gray65") +
        geom_text(size = odsm.scaled, alpha=alpha, color=clusters) +
        ggtitle(title)
}

#' This function uses igraph to plot the transition matrix as a network
#'
#' @param monsterObj monsterAnalysis Object
#' @param numEdges The number of edges to display
#' @param numTopTFs The number of TFs to display, ranked by largest dTFI
#' @return igraph object for transition matrix
#' @importFrom igraph graph.data.frame plot.igraph V E V<- E<-
#' @export
#' @examples
#' # data(yeast)
#' # design <- c(rep(0,20),rep(NA,10),rep(1,20))
#' # monsterRes <- monster(yeast$exp.cc, design, yeast$motif, nullPerms=100, numMaxCores=4)#' 
#' data(monsterRes)
#' transitionNetworkPlot(monsterRes)
#' 
transitionNetworkPlot <- function(monsterObj, numEdges=100, numTopTFs=10){
    ## Calculate p-values for off-diagonals
    transitionSigmas <- function(tm.observed, tm.null){
        tm.null.mean <- apply(simplify2array(tm.null), 1:2, mean)
        tm.null.sd <- apply(simplify2array(tm.null), 1:2, sd)
        sigmas <- (tm.observed - tm.null.mean)/tm.null.sd
    }
    
    tm.sigmas <- transitionSigmas(monsterObj@tm, monsterObj@nullTM)
    diag(tm.sigmas) <- 0
    tm.sigmas.melt <- melt(tm.sigmas)
    
    adjMat <- monsterObj@tm
    diag(adjMat) <- 0
    adjMat.melt <- melt(adjMat)
    
    adj.combined <- merge(tm.sigmas.melt, adjMat.melt, by=c("Var1","Var2"))
    
    # adj.combined[,1] <- mappings[match(adj.combined[,1], mappings[,1]),2]
    # adj.combined[,2] <- mappings[match(adj.combined[,2], mappings[,1]),2]
    
    dTFI_pVals_All <- 1-2*abs(.5-calculate.tm.p.values(monsterObj, 
                                                method="z-score"))
    topTFsIncluded <- names(sort(dTFI_pVals_All)[1:numTopTFs])
    topTFIndices <- 2>(is.na(match(adj.combined[,1],topTFsIncluded)) + 
        is.na(match(adj.combined[,2],topTFsIncluded)))
    adj.combined <- adj.combined[topTFIndices,]
    adj.combined <- adj.combined[
        abs(adj.combined[,4])>=sort(abs(adj.combined[,4]),decreasing=TRUE)[numEdges],]
    tfNet <- graph.data.frame(adj.combined, directed=TRUE)
    vSize <- -log(dTFI_pVals_All)
    vSize[vSize<0] <- 0
    vSize[vSize>3] <- 3
    
    V(tfNet)$size <- vSize[V(tfNet)$name]*5
    V(tfNet)$color <- "yellow"
    E(tfNet)$width <- (abs(E(tfNet)$value.x))*15/max(abs(E(tfNet)$value.x))
    E(tfNet)$color <-ifelse(E(tfNet)$value.x>0, "blue", "red")
    
    plot.igraph(tfNet, edge.arrow.size=2, vertex.label.cex= 1.5, vertex.label.color= "black",main="")
}

#' This function plots the Off diagonal mass of an 
#' observed Transition Matrix compared to a set of null TMs
#'
#' @param monsterObj monsterAnalysis Object
#' @param rescale logical indicating whether to reorder transcription
#' factors according to their statistical significance and to 
#' rescale the values observed to be standardized by the null
#' distribution 
#' @param plot.title String specifying the plot title
#' @param highlight.tfs vector specifying a set of transcription 
#' factors to highlight in the plot
#' @return ggplot2 object for transition matrix comparing observed 
#' distribution to that estimated under the null 
#' @export
#' @examples
#' # data(yeast)
#' # design <- c(rep(0,20),rep(NA,10),rep(1,20))
#' # monsterRes <- monster(yeast$exp.cc, design, yeast$motif, nullPerms=100, numMaxCores=4)#' 
#' data(monsterRes)
#' dTFIPlot(monsterRes)
dTFIPlot <- function(monsterObj, rescale=FALSE, plot.title=NA, highlight.tfs=NA){
    if(is.na(plot.title)){
        plot.title <- "Differential TF Involvement"
    }
    num.iterations <- length(monsterObj@nullTM)
    # Calculate the off-diagonal squared mass for each transition matrix
    null.SSODM <- lapply(monsterObj@nullTM,function(x){
        apply(x,2,function(y){t(y)%*%y})
    })
    null.ssodm.matrix <- matrix(unlist(null.SSODM),ncol=num.iterations)
    null.ssodm.matrix <- t(apply(null.ssodm.matrix,1,sort))

    ssodm <- apply(monsterObj@tm,2,function(x){t(x)%*%x})

    p.values <- 1-pnorm(sapply(seq_along(ssodm),function(i){
        (ssodm[i]-mean(null.ssodm.matrix[i,]))/sd(null.ssodm.matrix[i,])
    }))
    t.values <- sapply(seq_along(ssodm),function(i){
            (ssodm[i]-mean(null.ssodm.matrix[i,]))/sd(null.ssodm.matrix[i,])
    })

    # Process the data for ggplot2
    combined.mat <- cbind(null.ssodm.matrix, ssodm)
    colnames(combined.mat) <- c(rep('Null',num.iterations),"Observed")


    if (rescale){
        combined.mat <- t(apply(combined.mat,1,function(x){
            (x-mean(x[-(num.iterations+1)]))/sd(x[-(num.iterations+1)])
        }))
        x.axis.order <- rownames(monsterObj@nullTM[[1]])[order(-t.values)]
        x.axis.size    <- 10 # pmin(15,7-log(p.values[order(p.values)]))
    } else {
        x.axis.order <- rownames(monsterObj@nullTM[[1]])
        x.axis.size    <- pmin(15,7-log(p.values))
    }

    null.SSODM.melt <- melt(combined.mat)[,-1][,c(2,1)]
    null.SSODM.melt$TF<-rep(rownames(monsterObj@nullTM[[1]]),num.iterations+1)

    ## Plot the data
    ggplot(null.SSODM.melt, aes(x=TF, y=value))+
        geom_point(aes(color=factor(Var2), alpha = .5*as.numeric(factor(Var2))), size=2) +
        scale_color_manual(values = c("blue", "red")) +
        scale_alpha(guide = "none") +
        scale_x_discrete(limits = x.axis.order ) +
        theme_classic() +
        theme(legend.title=element_blank(),
            axis.text.x = element_text(colour = 1+x.axis.order%in%highlight.tfs, 
            angle = 90, hjust = 1, 
            size=x.axis.size,face="bold")) +
        ylab("dTFI") +
        ggtitle(plot.title)

}

#' Calculate p-values for a tranformation matrix
#'
#' This function calculates the significance of an observed
#' transition matrix given a set of null transition matrices
#'
#' @param monsterObj monsterAnalysis Object
#' @param method one of 'z-score' or 'non-parametric'
#' @return vector of p-values for each transcription factor
#' @export
#' @examples
#' # data(yeast)
#' # design <- c(rep(0,20),rep(NA,10),rep(1,20))
#' # monsterRes <- monster(yeast$exp.cc, design, yeast$motif, nullPerms=100, numMaxCores=4)#' 
#' data(monsterRes)
#' calculate.tm.p.values(monsterRes)
calculate.tm.p.values <- function(monsterObj, method="z-score"){
    num.iterations <- length(monsterObj@nullTM)
    # Calculate the off-diagonal squared mass for each transition matrix
    null.SSODM <- lapply(monsterObj@nullTM,function(x){
        apply(x,1,function(y){t(y)%*%y})
    })
    null.ssodm.matrix <- matrix(unlist(null.SSODM),ncol=num.iterations)
    null.ssodm.matrix <- t(apply(null.ssodm.matrix,1,sort))

    ssodm <- apply(monsterObj@tm,1,function(x){t(x)%*%x})

    # Get p-value (rank of observed within null ssodm)
    if(method=="non-parametric"){
        p.values <- sapply(seq_along(ssodm),function(i){
            1-findInterval(ssodm[i], null.ssodm.matrix[i,])/num.iterations
        })
    } else if (method=="z-score"){
        p.values <- pnorm(sapply(seq_along(ssodm),function(i){
            (ssodm[i]-mean(null.ssodm.matrix[i,]))/sd(null.ssodm.matrix[i,])
        }))
    } else {
        print('Undefined method')
    }
    p.values
}

globalVariables(c("Var1", "Var2","value","variable","xend","yend","y","Comp.1", "Comp.2","node.names","TF","i"))
