# -*- coding: utf-8 -*-
"""
Created on Tue Apr 23 09:17:18 2019

@author: nz9512
"""



import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
#import seaborn as sns
from sklearn.linear_model import LogisticRegression
from sklearn.cross_validation import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, f1_score, recall_score, accuracy_score, precision_score



col_names = ['Damage','Ductility','Creep_Rate','Zeta_P', 'A', 'S_y', 
'Alpha', 'C_f', 'Sigma_B', 'Sigma_SU', 'Sigma_RT', 'T_SU', 'T_RT', 'T_SO', 'Sigma_SO']

MCS_Res_Base = pd.read_csv('MCS_1000_Tube_29_D_LHC.csv', 
                           index_col = False, names = col_names)
MCS_Res_Target = pd.read_csv('MCS_10000_Tube_29_D_LHC.csv', 
                             index_col = False, names = col_names)

Failure_Limit = 0.5 # When modelling creep-fatigue damage, a value >= 1 failure (or more specifically the formation of a shallow crack)

#plt.figure(figsize= (10,6))
#MCS_Res_Base['Damage'].hist(bins = 30)

plt.figure(figsize= (10,6))
plt.scatter(MCS_Res_Base['Ductility'],
            MCS_Res_Base['Creep_Rate'],
            s = (MCS_Res_Base['Damage']*200))
plt.xlim(0,len(MCS_Res_Base['Damage']))
plt.ylim(0,len(MCS_Res_Base['Damage']))
plt.xlabel('Creep Ductility (low-high)')
plt.ylabel('Creep Strain Rate (slow-fast)')
plt.show()



X = MCS_Res_Base[['Ductility','Creep_Rate', 'A', 'S_y', 'Alpha', 'C_f']]
y = (MCS_Res_Base['Damage'] >= Failure_Limit)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.20)

logmodel = LogisticRegression()
logmodel.fit(X_train,y_train)
predictions = logmodel.predict(X_test)
print(classification_report(y_test,predictions))


X = MCS_Res_Base[['Ductility','Creep_Rate', 'A', 'S_y', 'Alpha', 'C_f']]
y = (MCS_Res_Base['Damage'] >= Failure_Limit)

X_Target = MCS_Res_Target[['Ductility','Creep_Rate', 'A', 'S_y', 'Alpha', 'C_f']]
y_Target = (MCS_Res_Target['Damage'] >= Failure_Limit)

logmodel = LogisticRegression()
logmodel.fit(X,y)
predictions = logmodel.predict(X_Target)
print(classification_report(y_Target,predictions))
print(confusion_matrix(y_Target,predictions))

# def Class_MCS_Trials(MCS_Res_Base, MCS_Res_Target):
    
    
    