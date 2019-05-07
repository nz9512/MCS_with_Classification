# MCS_with_Classification

## At a Glance
MCS probabilistic calculation with machine-learning classification to reduce the number of runs needed to calculate failure probabilities.

## IMPORTANT NOTE
Most of the files under this project are still under development. This repository was created to demonstrate a key problem in probabilistic structural integrity applications and propose possible solutions using machine-learning classification algorithms. 

## Background
This small project is an exploration of an area of work that I identified towards the end of my PhD project which was concerned (in part) with the estimation of probabilities of failure (PoF) of metallic components within power generation plants using Monte-Carlo simulations (MCS). 

In conventional structural integrity safety applications, it is common to calculate a 'damage' parameter based on a plethora of input parameters and conditions (e.g. relating to material properties, plant loads and loading histories) to ascertain whether a component is near failure. It must be clarified that 'failure' is defined depending on the application e.g. for creep-fatigue failure (which is the failure mode which I considered for my PhD) implies the formation of a shallow crack on the surface of a steel component. 
The core idea is to use a MCS which does repeated calculations of the damage parameter using 'N' number of input parameter samples. Thus N number of MCS trials are conducted with the combinations of input samples being arranged either randomly or using a Latin-hypercube strategy (the latter was used). After calculating the damage parameter for all N trials, the PoF is calculated as the fraction of the trails that have incurred damage larger than a predefined limit (e.g. for creep-fatigue damage of >=1 would be considered a failure). 

A key problem when conducting a MCS as per described above is that a single damage calculation (of which there is N number) can be computationally expensive (~0.5-3 min each) and therefore doing a large number of such calculations can be prohibitive. Using strategies such as vectorisation in Matlab, this problem can be significantly alleviated but, nevertheless, when N >= 10^5, the execution time of a single MCS can take days. This problem is compounded by the fact that a number of simulations may be required to assess the safety of a single component (e.g. many points on a single component may develop a crack) to calculate a component-level PoF. 

## This Project
For my PhD, I conducted simulations to estimate the PoF of specific points on a plant component (called the tubeplate ligament or TPL), which was implemented in Matlab using a vectorisation strategy (see TPL_MCS.m in the repository). If calculating PoFs is the only concern, then calculating all N possible damages isn't necessary; indeed only the trials that lead to failure are the ones needed. If only those are calculated, then the computational time required for a single MCS can be monumentally reduced e.g. I did simulations with 10^4 trails (MCS_10000_Tube_2_D_LHS.csv) and only 156 out 10^4 failed. 
So here is the premise of this project: what if a machine-learning algorithm can be trained to use the results from a computationally cheap 10^3 MCS to identify the trails in a computationally expensive 10^4 simulation that are most likely to fail? This is essentially a classification problem with the 10^3 results data being using to train a model in order to classify the 10^4 trails into 'likely to fail' and 'not likely to fail'. If this classification is successful, then only a fraction of the 10^4 MCS trials would require evaluating, therefore saving significant computational efforts. To clarify, the classification strategy is NOT intended to predict the MCS results, but rather to target the ones that are needed to calculate the PoF, and as such it doesn't predict anything but rather focuses and saves computational efforts.  This classification strategy would be undoubtedly valuable if a MCS with a very large N is required (e.g. N >= 10^6) which would normally take days to run, but with the classification strategy may take mere hours.

## Files in this Repository
### Matlab Script (TPL_MCS.m)
This is the Matlab script that I wrote for my PhD and was used to produce the results for 10^3,10^4, and 10^5 trials (see the results files). When evaluating all trails, these three sets of MCS results took on average 30min, 2 hour and 9 hours respectively.  In this script, two key inputs are 'Nb' and 'Tubes', the former being the number of MCS trials required and the latter referring to the intended assessment location (which are the tubes in the TPL component; 37 tubes in total). 
 
### Python Script (Classification_for_MCS.ipynb)
This is a Python script (Jupyter Notebook) that I'm developing using machine learning classification (Scikit-Learn) in order to reduce the number of MCS trails. For this script to run, only the results files (see below) are required. 

### Results files
The names of these files have the format MCS_N_Tube_T_D_LHC.csv where 'N' being the number of MCS trials which was used to produce those results by the TPL_MCS.m script and 'T' refers to a single tube in the TPL component (the TPL has 37 tubes in total). Results for 10^3,10^4 and 10^5 MCS trials from tubes 2 and 29 are included in the repository.

### All Other Files 
The remaining files are input files required for the TPL_MCS.m script to run.



  
