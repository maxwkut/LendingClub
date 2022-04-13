#title: 'STAT656: Lending Club Project'
#subtitle: Predict which loans will become "Charged Off" or "Fully Paid"
---
#Used Logistic Regression and LDA to predict this.


#DATA PREPROCESSING for predicting "charged off" vs "fully paid"
  

#loading objects and data
packs = c('dplyr','ggplot2', 'caret','corrplot', 'e1071','readr', 'pROC', 'glmnet')
lapply(packs,require,character.only=TRUE)

dataSet = read_csv('LoanStats3a.csv')

X = filter(dataSet, loan_status == 'Charged Off' | loan_status == 'Fully Paid')

#Checking the structure of X 
str(X)


#some of these columns we likely wont be able to gather any useful 
#information from so I removed them
X = select(X, -c(id, member_id, emp_title, url, desc, zip_code))


#lots of columns with large amount of NA's so I removed them
X = X[ ,colSums(is.na(X))/nrow(X) < 0.5]
str(X)

#Now that the list of features is smaller I am double checking
#the columns to see if there are any features that are unusable.
       
#title - too many levels
#open_acc - too many unique values
#initial_list_status - ?
#chargeoff_within_12_mths - only 2 values, 0 and blank
#acc_now_delinq - no borrower has delinq accounts.
#delinq_amnt - !need to check if it can be used!
#collections_12_mnths_ex_med - only has 0 or blanks
#policy_code - not usable has a unique value for each row
#tax_liens - only has 0 and NA values
#addr_state - too many factors and would create too many dummy variables?

X = select(X, -c(title, 
                 open_acc, 
                 initial_list_status, 
                 chargeoff_within_12_mths, 
                 acc_now_delinq, 
                 delinq_amnt,
                 collections_12_mths_ex_med,
                 policy_code,
                 tax_liens,
                 addr_state))

#I am trying to keep only the features that are available to us before someone invested on the loan.
#I think these features were not available before loan disbursement

X = select(X, -c(total_pymnt, 
              total_pymnt_inv, 
              total_rec_prncp, 
              total_rec_int, 
              total_rec_late_fee, 
              recoveries, 
              collection_recovery_fee,
              last_pymnt_d,
              last_pymnt_amnt,
              ))

#Assigning the appropriate data class to our features
#and to the supervisor
table(sapply(X[1,],class))
str(X)

X = mutate_at(X, vars(term, 
                      grade,
                      sub_grade,
                      home_ownership,
                      verification_status,
                      pymnt_plan,
                      purpose,
                      application_type,
                      loan_status), as.factor)

X$int_rate = sub("%", "", X$int_rate) %>% as.numeric(.)

    #I dont really know if it is possible to represent "10+ years" and "<1year" as numeric
    #so I am just going to change them to 10 and 0
X$emp_length[which(X$emp_length == "10+ years")] = 10
X$emp_length[which(X$emp_length == "< 1 year")] = 0
X$emp_length[which(X$emp_length == "n/a")] = NA
X$emp_length = sub(" years", "", X$emp_length)
X$emp_length = sub(" year", "", X$emp_length)
X$emp_length = as.numeric(X$emp_length)


X$issue_d = sub("-.*", "", X$issue_d) %>% as.factor(.)
#X$zip_code = sub("xx", "", X$zip_code) %>% as.numeric(.)
    #X$addr_state = as.factor(X$addr_state) too many factors?

    #I think the year this was last updated was 2016
    #Im going to convert earliest_cr_line to the number of years
    #since their earliest credit line.
X$earliest_cr_line = sub(".*-", "", X$earliest_cr_line) %>% as.numeric(.)

current = 16 - X$earliest_cr_line[X$earliest_cr_line < 20]
old = X$earliest_cr_line[X$earliest_cr_line > 20] %>% as.character(.)
old = paste("19",old)
old = sub(" ","", old) %>% as.numeric(.)
old = 2016 - old
current = as.character(current)
old = as.character(old)
X$earliest_cr_line = as.numeric(c(current, old))

X$revol_util = sub("%", "", X$revol_util) %>% as.numeric(.)
X$last_credit_pull_d = sub("-.*", "", X$last_credit_pull_d) %>% as.factor(.)

#Creating a new X variable for handling extreme observations
Xextreme = X

#Center and scale the features where they are numeric
X = X %>% preProcess(.) %>% predict(newdata = X)
str(X)

#application_type factor only has 1 level so ill remove it
X = select(X, -application_type)

#Removing features that do not have at least some nontrivial variation
sdVec = rapply(X,f=sd,classes="numeric",na.rm=TRUE)
which(sdVec < 0.0001)
X = select(X, -c(out_prncp,
                 out_prncp_inv))

#Checking the skewness for the numeric features
# LDA requires features to have normal distribution
skewnessVec = X %>% rapply(.,f=e1071::skewness,classes="numeric",na.rm=TRUE)
skewnessVec

skewFeats = names(which(abs(skewnessVec) >1))

#Correcting skewness (maybe I dont have to do this)
XskewYJ = X %>% select(contains(skewFeats)) %>%
  preProcess(method = 'YeoJohnson', na.rm=TRUE) %>%
  predict(X %>% select(contains(skewFeats)))

XnotSkew = X %>% select(!contains(skewFeats))

sapply(XskewYJ, skewness, na.rm=TRUE)
rapply(XnotSkew, skewness, classes="numeric", na.rm=TRUE)

X = cbind(XskewYJ, XnotSkew)

#Checking for extreme observations using PCA
Xnumeric = select_if(X, is.numeric)
pcaOut = prcomp(na.omit(Xnumeric),scale=TRUE,center=TRUE)
XnumericyeoJscores = data.frame(pcaOut$x)
ggplot(data = XnumericyeoJscores) +
  geom_point(aes(x = PC1, y = PC2)) +
  coord_cartesian(xlim = range(XnumericyeoJscores$PC1), ylim = range(XnumericyeoJscores$PC2))


#   Checking out the extreme observations in PC2
(extremeObs = which(XnumericyeoJscores$PC2 > 8))
str(Xextreme[, ])


# I checked out these outliers and it doesn't look like there
# were any mistakes made in their entries so I am going to keep them


#cleaning up
rm(list= ls()[!ls() %in% 'X'])


#Separating data into training and test sets and handling the class imbalance.
str(X)
set.seed(1)
n = nrow(X)
trainingDataIndex = createDataPartition(X$loan_status, p = .5, list = FALSE) %>% as.vector(.)
trainingData = X[trainingDataIndex, ]
#downsampling to balance the class imbalance
predictors = select(trainingData, -loan_status)
outcome = select(trainingData, loan_status) %>% unlist(.)
trainingData = downSample(x=predictors, y=outcome, yname='loan_status')
testingData = X[-trainingDataIndex, ]

Xtrain = select(trainingData, -loan_status)
Xtest = select(testingData, -loan_status)
Ytrain = select(trainingData, loan_status) %>% unlist()
Ytest = select(testingData, loan_status) %>% unlist()

rm(trainingData)
rm(testingData)

#Check again for missing data
sapply(Xtrain, function(x) sum(is.na(x))) 
sapply(Xtest, function(x) sum(is.na(x))) 

#imputing values for these features

    #Using corrplot to see if features can be imputed using a linear model
require(corrplot)
corrX = select_if(X, is.numeric)
str(corrX)
corrplot(cor(corrX, use="complete.obs"), tl.cex=0.5)

    #Using pub_rec to predict missing values in pub_rec_bankruptcies
trControl = trainControl(method = 'none')

imputationScheme = train(pub_rec_bankruptcies~pub_rec,
                         data=select(Xtrain, pub_rec, pub_rec_bankruptcies) %>% na.omit,
                         method='lm', trControl=trControl)
XtrainImp = Xtrain
M = is.na(XtrainImp$pub_rec_bankruptcies)
XtrainImp$pub_rec_bankruptcies[M]=predict(imputationScheme,
                                          select(Xtrain, pub_rec, pub_rec_bankruptcies) %>%
                                            filter(M))

    #Imputing for the for the test data pub_rec_bankruptcies 
imputationScheme = train(pub_rec_bankruptcies~pub_rec,
                         data=select(Xtest, pub_rec, pub_rec_bankruptcies) %>% na.omit,
                         method='lm', trControl=trControl)
XtestImp = Xtest
M_test = is.na(XtestImp$pub_rec_bankruptcies)
XtestImp$pub_rec_bankruptcies[M_test]=predict(imputationScheme,
                                          select(Xtest, pub_rec, pub_rec_bankruptcies) %>%
                                            filter(M_test))

    #Using annual_inc to predict emp_length
trControl = trainControl(method = 'none')

imputationScheme = train(emp_length~annual_inc,
                         data=select(Xtrain, annual_inc, emp_length) %>% na.omit,
                         method='lm', trControl=trControl)

M = is.na(XtrainImp$emp_length)
XtrainImp$emp_length[M]=predict(imputationScheme,
                                          select(Xtrain, annual_inc, emp_length) %>%
                                            filter(M))

    #Imputing for the for the test data emp_length 
imputationScheme = train(emp_length~annual_inc,
                         data=select(Xtest, annual_inc, emp_length) %>% na.omit,
                         method='lm', trControl=trControl)

M_test = is.na(XtestImp$emp_length)
XtestImp$emp_length[M_test]=predict(imputationScheme,
                                              select(Xtest, annual_inc, emp_length) %>%
                                                filter(M_test))

    #using revol_bal to predic revol_util
trControl = trainControl(method = 'none')

imputationScheme = train(revol_util~revol_bal,
                         data=select(Xtrain, revol_bal, revol_util) %>% na.omit,
                         method='lm', trControl=trControl)

M = is.na(XtrainImp$revol_util)
XtrainImp$revol_util[M]=predict(imputationScheme,
                                select(Xtrain, revol_bal, revol_util) %>%
                                  filter(M))

    #Imputing for the for the test data revol_util
imputationScheme = train(revol_util~revol_bal,
                         data=select(Xtest, revol_bal, revol_util) %>% na.omit,
                         method='lm', trControl=trControl)

M_test = is.na(XtestImp$revol_util)
XtestImp$revol_util[M_test]=predict(imputationScheme,
                                    select(Xtest, revol_bal, revol_util) %>% 
                                     filter(M_test))


    #Imputing the mode for last_credit_pull_d
tbl = table(X$last_credit_pull_d)
XtrainImp$last_credit_pull_d[is.na(Xtrain$last_credit_pull_d)] = names(tbl)[which.max(tbl)]
XtestImp$last_credit_pull_d[is.na(Xtest$last_credit_pull_d)] = names(tbl)[which.max(tbl)]

    #Double check missing
sapply(XtrainImp, function(x) sum(is.na(x))) 
sapply(XtestImp, function(x) sum(is.na(x))) 

########Testing out removing features
########pg45 reccomends removing features if imbalanced frequencies and fraction of 
######## unique values to sample size is low
str(XtrainImp)
nearZeroVar(XtrainImp, saveMetrics = TRUE)
table(XtrainImp$pub_rec_bankruptcies)
table(XtrainImp$pymnt_plan)

XtrainImp = select(XtrainImp, -c(pub_rec_bankruptcies,
                                 pymnt_plan))
XtestImp = select(XtestImp, -c(pub_rec_bankruptcies,
                               pymnt_plan))

#Correlation filtering to remove highly correlated features
corrXtrain = select_if(XtrainImp, is.numeric)
corrplot(cor(corrXtrain), tl.cex = 0.5)
(highcorr = findCorrelation(cor(corrXtrain), cutoff = 0.8))

XtrainImp = select(XtrainImp, -any_of(highcorr))
XtestImp = select(XtestImp, -any_of(highcorr))

str(XtrainImp)
str(XtestImp)

corrXtrain = select_if(XtrainImp, is.numeric)
corrplot(cor(corrXtrain), tl.cex = 0.5)

#Dummy variable coercion and creating full feature matrices
XtrainImpFact = select_if(XtrainImp, is.factor)
XtestImpFact = select_if(XtestImp, is.factor)

dummyModel = dummyVars(~., data = XtrainImpFact, fullRank= TRUE)

XtrainQualDummy = predict(dummyModel, XtrainImpFact)
XtrainQuan = select_if(XtrainImp, is.numeric)
XtrainFull = cbind(XtrainQualDummy, XtrainQuan)

XtestQualDummy = predict(dummyModel, XtestImpFact)
XtestQuan = select_if(XtestImp, is.numeric)
XtestFull = cbind(XtestQualDummy, XtestQuan)

#Trying logistic regression
YtrainRelevel = relevel(Ytrain, ref = 'Charged Off')
YtestRelevel = relevel(Ytest, ref = 'Charged Off')
trControl = trainControl(method = 'none')

outLogistic = train(x = XtrainFull, y = YtrainRelevel,
                    method = 'glm', trControl = trControl)
summary(outLogistic)

YhatTestProb = predict(outLogistic, XtestFull, type = 'prob')
head(YhatTestProb)

#Checking how well calibrated the probabilities are
calibProbs = calibration(YtestRelevel ~ YhatTestProb$`Charged Off`)
xyplot(calibProbs)

#Getting default confusion matrix
YhatTest = predict(outLogistic, XtestFull, type = 'raw')
confusionMatrixOut = confusionMatrix(reference = YtestRelevel, data = YhatTest)
print(confusionMatrixOut$table)
print(confusionMatrixOut$overall[1:2])
print(confusionMatrixOut$byClass[1:2])

#ROC curve
rocCurve = roc(Ytest, YhatTestProb$`Charged Off`)
plot(rocCurve, legacy.axes=TRUE)
rocCurve$auc

thresholds = rocCurve$thresholds
sort(thresholds)[1:3]

sort(thresholds, decreasing = TRUE)[1:3]

#Getting confusion matrix for particular sensitivity

pt5 = which.min(rocCurve$sensitivities >= 0.8) 
threshold = thresholds[pt5]
specificity = rocCurve$specificities[pt5]
sensitivity = rocCurve$sensitivities[pt5]

YhatTestThresh = ifelse(YhatTestProb$`Charged Off` > threshold,
                        'Charged Off', 'Fully Paid') %>% as.factor()

confusionMatrixOut = confusionMatrix(reference = YtestRelevel, data = YhatTestThresh)
confusionMatrixOut$table
print(confusionMatrixOut$overall[1:2])
print(confusionMatrixOut$byClass[1:2])



#Linear Discriminate Analysis (LDA)

trControl = trainControl(method = 'none')
outLDA = train(x = XtrainFull[,-42], y = YtrainRelevel,
               method = 'lda', trControl = trControl)

YhatTestProbLDA = predict(outLDA, XtestFull, type = 'prob')
head(YhatTestProbLDA)

#calibration plot
calibProbs = calibration(YtestRelevel ~ YhatTestProbLDA$`Charged Off`)
xyplot(calibProbs)

#Confusion Matrix for default threshold
YhatTestLDA = predict(outLDA, XtestFull, type = 'raw')
confusionMatrixOutLDA = confusionMatrix(reference = YtestRelevel, data = YhatTestLDA)
print(confusionMatrixOutLDA$table)
print(confusionMatrixOutLDA$overall[1:2])
print(confusionMatrixOutLDA$byClass[1:2])

#ROC curve and AUC
rocCurveLDA = roc(Ytest, YhatTestProbLDA$`Charged Off`)
plot(rocCurveLDA, legacy.axes=TRUE)
rocCurveLDA$auc

#Getting confusion matrix for particular sensitivity
thresholdsLDA = rocCurveLDA$thresholds
pt5LDA = which.min(rocCurveLDA$sensitivities >= 0.8) 
thresholdLDA = thresholds[pt5LDA]
specificityLDA = rocCurveLDA$specificities[pt5LDA]
sensitivityLDA = rocCurveLDA$sensitivities[pt5LDA]

YhatTestThreshLDA = ifelse(YhatTestProbLDA$`Charged Off` > threshold,
                        'Charged Off', 'Fully Paid') %>% as.factor


confusionMatrixOutLDA = confusionMatrix(reference = YtestRelevel, data = YhatTestThreshLDA)
print(confusionMatrixOutLDA$table)
print(confusionMatrixOutLDA$overall[1:2])
print(confusionMatrixOutLDA$byClass[1:2])



