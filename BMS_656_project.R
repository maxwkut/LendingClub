#title: 'STAT656: Lending Club Project'
#subtitle: Predict which loans will become "Charged Off" or "Fully Paid"
---
#Give longer summary of what we plan to do here.


#DATA PREPROCESSING for predicting "charged off" vs "fully paid"
  

#loading objects and data
packs = c('dplyr','ggplot2', 'caret','corrplot', 'e1071','readr')
lapply(packs,require,character.only=TRUE)

dataSet = read_csv('LoanStats3a.csv')

df = filter(dataSet, loan_status == 'Charged Off' | loan_status == 'Fully Paid')


Y = select(df,loan_status) %>% unlist()
X = select(df,-loan_status)


#Checking the structure of X and Y data
str(Y)
str(X)


#some of these columns we likely wont be able to gather any useful information from so I removed them
X = select(X, -c(emp_title, url, desc, zip_code))


#lots of columns with large amount of NA's so I removed them
X = X[ ,colSums(is.na(X))/nrow(X) < 0.5]
str(X)

#Checking which columns still have NA's in them
sapply(X, function(x) sum(is.na(x)))
       
#Now that the list of features is smaller I am going to double check the columns to see if there are any features that are unusable. I am also going to try and keep only the features that are available to the investor before they invested on the loan.
       
#title - too many levels
#open_acc - too many unique values
#initial_list_status - ?
#chargeoff_within_12_mths - only 2 values, 0 and blank
#acc_now_delinq - no borrower has delinq accounts.
#delinq_amnt - !need to check if it can be used!

X = select(X, -c(title, open_acc, initial_list_status, chargeoff_within_12_mths, acc_now_delinq))

#Now I am going to check it again to see which features have missing values.
sapply(X, function(x) sum(is.na(x)))
ncol(X)


#I havent actually done anything below this yet




#Now we need to impute data where there is still missing values

#Removing the columns that do not have at least some nontrivial variation.
sdVec = apply(X,2,sd,na.rm=TRUE)
X = select_if(X,sdVec > 0.0001)
str(X)

#Assigning the appropriate data type to our features.
unique(X$term)

#center and scale the numeric data



