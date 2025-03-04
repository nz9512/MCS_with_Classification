
function TPL_MCS

clc; close all; clear all;

% Setting the type of calculation:
% 1. 'Probabilistic': a MCS which includes 15 probabilistic input
% parameters and all other input variables set to median values
% 2. 'Deterministic': uses median values for all input parameters 

AnalysisType = 'Probabilistic'; % 

% Set the number of MCS assessments by choosing the number of tubes to be
% examined. TubeOrderByPoI is the order of assessment locations (i.e. tubes)
% in order of descending probaiblity of failure (PoI, I = crack
% initiation). Currently only the tubes with the highest 
% PoI (e.g. TubeOrderByPoI(1:10)) are set to be examined.

load('TubeOrderByPoI.mat'); 
Tubes = TubeOrderByPoI(1); % Tubes = TubeOrderByPoI(1:37)';


% Number of bin in the latin-hyerpercube per input parameter:
Nb = 1000;

% Conducting the MCS
[TotalDamage, LHS] = TPL_Prob_Asmt_V7(Nb,Tubes,AnalysisType);


end


function [TotalDamage, LHS] = TPL_Prob_Asmt_V7(Nb,Tubes,AnalysisType)

format long

%% Setttings for the code

Reset_Settings = 1; % This refers to the reshuffling of the latin-hypercube 
Repeat_History_Data_Analysis = 0;
Repeat_Transient_Sampling = 0;
ReprepareWorkspace = 0;
Plot_SS_Temp_Histograms = 0;
Plot_SO_Samples = 0;
Plot_Transient_Histograms = 0;

No_Asmt_Locations_Per_Tube = 1;
Corr_SA = 0;
CorrType = 'Spearman';
PR_Options = 'PR'; % 'PR' OR 'CH' OR 'Zeta_P'


%% Files' names

Asmt_Sets_Filename = ['Asmt_Sets_' num2str(Nb) '_Trials.mat'];
WorkSpace_Filename = ['WorkSpace_' num2str(Nb) '_Trials.mat'];

Resultsfilename = ['Res_' AnalysisType '_Nb_' num2str(Nb) '_All_Tubes.mat'];


% The analysis settings were kept fixed during the develpment stages of
% this code (i.e. Reset_Settings = 0) but can be reset for future runs by
% setting Reset_Settings = 1.

if Reset_Settings
    
    %% Creep relaxation settings
    
    DefultStrainIncrement = 1e-6; % This is in abs
    Int_Time_Resolution_Factor = 0.0001;
    Reduce_Int_Conservatism = 0; % 0 gives more conservative damages (test case: 20% higher damages but it's 25% faster)
    
    
    %%  1. MCS and LHS inputs
    % 2. LHS bins for the main parameters
    % Note: the same LHS permutations are used for material properties for all tubes.
    % That's why the LHS is taken out of the tubes' loop.
    % 3. Correlating the bins for creep strain rate and creep ductility
    
    Nv = 15;  % Number of variables
    
    % P1: Ductility (Varep_f)
    % P2: Creep Strain Rate
    % P3: Primary Reset Zeta factor
    % P4: A in Ramberg-Osgood expression
    % P5: Proof-Stress
    % P6: Young's Modulus
    % P7: Coefficient of thermal expansion
    % P8: Fatigue endurance uncertainty
    % P9: Sigma_B, but only for the deterministic case
    % P10: SU Most dominant stress component
    % P11: RT Most dominant stress component
    % P12: SU temperature
    % P13: RT temperature
    % P14: SO/Event temperature
    % P15: SO/Event Most dominant stress component
    
    switch AnalysisType
        case 'Probabilistic'
            LHS = LHS_Permutations(Nb,Nv);
            [LHS,~] = Correlated_Bins(LHS,1,2,0.545); % 0.545 is the mean correlation found from my work on correlations  
        case 'Deterministic'
            LHS = ones(1,15).*Nb/2; % The +1 is to include the start of dwell stress       
    end

    save(Asmt_Sets_Filename)
    
else
    load(Asmt_Sets_Filename)
end

%% Preparing a workspace that's shared by all tubes


if ReprepareWorkspace
    PrepareWorkSpace(Asmt_Sets_Filename,WorkSpace_Filename)
end

%% Parallel pool

% Parallel for-loop is only set to work if more than one tube is being
% asseessd. Parallelisation of the MCS trials is done simply by using
% vectorisation. 

% if Start_Parallel_Pool = 1, then N_Workers needs to be set manually. 
% On an 8-core machine, 4-6 workers work well while keeping enough memory 
% and cpu for the machine to do other functions.

Start_Parallel_Pool = 0;
N_Workers = 2; 

if Start_Parallel_Pool
    delete(gcp)
    parpool(N_Workers);
end

%% Run the assessment

t = tic();

if Start_Parallel_Pool
    
    parfor T = 1:length(Tubes)
        
        [TotalDamage{T},TotalDamage_By_Cycle{T}] = R5_Assessment(Tubes(T),WorkSpace_Filename,LHS);
        
        csvwrite(['MCS_' num2str(Nb) '_Tube_' num2str(Tubes(T)) '_D_LHC.csv'],[TotalDamage{T} LHS])
        csvwrite(['MCS_' num2str(Nb) '_Tube_' num2str(Tubes(T)) '_DbC.csv'],cell2mat(TotalDamage_By_Cycle{T}))
       
    end

else
    
    for T = 1:length(Tubes)
        
        [TotalDamage{T},TotalDamage_By_Cycle{T}] = R5_Assessment(Tubes(T),WorkSpace_Filename,LHS);
        
        csvwrite(['MCS_' num2str(Nb) '_Tube_' num2str(Tubes(T)) '_D_LHC.csv'],[TotalDamage{T} LHS])
        csvwrite(['MCS_' num2str(Nb) '_Tube_' num2str(Tubes(T)) '_DbC.csv'],cell2mat(TotalDamage_By_Cycle{T}))

    end
    
end

Elapsed_Time = toc(t);
disp(['Total analysis time = ' num2str(Elapsed_Time./60) 'min'])


% Mapping the failied trials onto the ductility distribution

figure; whitebg('w');set(gcf,'color','w');
plot(LHS((TotalDamage{T} > 1),1)',LHS((TotalDamage{T} > 1),2)','xr','MarkerSize',14,'LineWidth',2);  hold on;
plot(LHS(:,1)',LHS(:,2)','.k','MarkerSize',14,'LineWidth',2);
xlabel('Ductility latin-hypercube bins (low to high)','FontSize', 12);ylabel('Creep rate latin-hypercube bins (slow to fast)','FontSize', 12);
set(gca,'FontSize',12,'fontWeight','bold');
set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
set(gca,'LineWidth',2);

legend(['Initiated trials - ' num2str(sum(TotalDamage{T} > 1)) ' out of ' num2str(length(TotalDamage{T}))])
set(gcf, 'Position', [50 50 750 750]);


end

%% Assessment Code

function [TotalDamage,TotalDamage_By_Cycle] = R5_Assessment(Assess_Tube,WorkSpace_Filename,LHS)


load(WorkSpace_Filename)

Tube = Assess_Tube;

All_Temps = ArrayInputData(:,Tube+2);

clear ArrayInputData % Don't need this beyond this point

%% Cleaning the temperature data

% Replace erroneous measurements with deterministic temperatures according to the modes

for m = 1:8
    [Mode_Temp(m,1),Modes_Str_Components(m,:)] = TempStress_Deterministic(m); % Stress compoentns and temperatures for each mode
end

Mask = (isnan(All_Temps) + ...
    (All_Temps > 1000) + ...
    (All_Temps < 400).*(All_Temps ~= 0));

Mask(Mask~=0)=1;

if sum(Mask)
    All_Temps(Mask==1) = Mode_Temp(Modes(Mask==1));
end


%% Prepare transients for probabilistic assessment

if Repeat_Transient_Sampling
    [SU_Strs_Samples,SU_Temps_Samples,RT_Strs_Samples,RT_Temps_Samples] = AssignCycleTransients(Nb,LHS,CycleNo,Tube,Plot_Transient_Histograms,AnalysisType);
    save(['Transient_Inputs_' num2str(Nb) '_Samples.mat'],'SU_Strs_Samples','SU_Temps_Samples','RT_Strs_Samples','RT_Temps_Samples')
else
    load(['Transient_Inputs_' num2str(Nb) '_Samples.mat']);
end

%% Qunatities related to BT and RC transients (these are incorprated within the history loop later)

BoilerCyles = [104:105 116:117 152:153];

RC_Temp = 505.9;
BT_Temp = 358.9;

RC_Str_Factor = 1.46;
BT_Str_Factor = 1.09;


%% # Input  : Probabilistic steady state stresses as functions of tilt

A = 1; % This is the number of assessment locations. A = 1 means looking at the FE node that most frequently had the most stresses location

dT_MetalTemp_Samples = [];

clear All_Str_Comps

switch AnalysisType
    case 'Probabilistic'
        load(['Sampled_Stresses_and_Metal_Temperature_' num2str(Nb) '_Samples_Tube_' num2str(Tube) '_Asmt_Loc_' num2str(A) '.mat']);
    case 'Deterministic'
        load(['Sampled_Stresses_and_Metal_Temperature_' num2str(1000) '_Samples_Tube_' num2str(Tube) '_Asmt_Loc_' num2str(A) '.mat']);
end


Prob_Str_Comps{Tube} = All_Str_Comps{A};
dT_MetalTemp_Samples{Tube} = dT_Samples{A};


if Plot_SO_Samples
    Validate_Samples_against_FE(Prob_Str_Comps,No_Asmt_Locations_Per_Tube,Tubes,Nb,CycleNo);
end


%% Clear unneeded parameters

clear dT_Samples % Don't need this boyond this point


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% START OF ASSESSMENT %%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

switch AnalysisType
    case 'Probabilistic'
        Nbb = Nb;
    case 'Deterministic'
        Nbb = 1;
end

CycleStartStress = zeros(Nbb,1);
Fatigue_Damage = zeros(Nbb,1);
Prob_Fail = zeros(CycleNo,1);
Mean_Log_Damage = zeros(CycleNo,1);
STD_Log_Damage = zeros(CycleNo,1);
Total_Strain_Range = zeros(CycleNo,1);
EndEventCreepStrain = zeros(length(Dwell_Times),5);
EndEventCreepRate= zeros(length(Dwell_Times),5);
EndEventCreepDamage = zeros(length(Dwell_Times),5);
StartEventDwellStress = zeros(length(Dwell_Times),5);
EndEventDwellStress = zeros(length(Dwell_Times),5);
Initial_TotalDamage_By_Cycle = zeros(Nb,1);
EndCreepDamage = zeros(Nb,1);

AllCycleTemps = [];


%% Prepare the transients for the first cycle

switch AnalysisType
    case 'Probabilistic'
        SU_RandPerm = randperm(Nb)';% Keep the same permutation for stresses and temperatures
        Prob_SU_Strs{Tube,1} = SU_Strs_Samples{Tube,1}(SU_RandPerm,:);
        Prob_SU_Temps{Tube,1} = SU_Temps_Samples{Tube,1}(SU_RandPerm);
        
        RT_RandPerm = SU_RandPerm ; % For RTs use the same perm
        Prob_RT_Strs{Tube,1} = RT_Strs_Samples{Tube,1}(RT_RandPerm,:);
        Prob_RT_Temps{Tube,1} = RT_Temps_Samples{Tube,1}(RT_RandPerm);
        
    case 'Deterministic'
        
        Prob_SU_Strs{Tube,1} = SU_Strs_Samples{Tube,1};
        Prob_SU_Temps{Tube,1} = SU_Temps_Samples{Tube,1};
        
        Prob_RT_Strs{Tube,1} = RT_Strs_Samples{Tube,1};
        Prob_RT_Temps{Tube,1} = RT_Temps_Samples{Tube,1};
        
end

%% Start counter and set the initial stress permutation 

Cycle_Counter = 1;

rng('shuffle');
Str_MetTemp_Perm = randperm(Nb); % Initial Stress AND Metal Temp Permutation, and then it chages every cycle


%% History for loop

for Event_No = 1:length(Dwell_Times)
    
    if Dwell_Times(Event_No) ~= 0
        
        if CycleEventNo(Event_No) == 1
            
            %% Half cycle without creep dwell
            % Properties and parameters are taken at the max temperature for this half cycle
            
            T_Hot = round(max([Prob_RT_Temps{Tube,1},SD_Temp,Prob_SU_Temps{Tube,1}],[],2),4, 'significant');
            
            Temp_Index = FindExtrapIndex(T_Hot,Extrap_Temps); % This find the indeies of Extrap_Temps corrisponding to the elements in T_Hot
            
            % E_bar corrisponds to Parameter 6 in the LHS matrix
            E_bar =   E_bar_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,6)).*(STD_E_Bar(Temp_Index)');
            
            % ESF - This has the same permutation as E_Bar, so the 6th colomn of LHS
            ESF = (E_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,6)).*(STD_E(Temp_Index)'))./E_at_Temp(Temp_Index)';
            
            % A corrisponds to Parameter 4 in the LHS matrix
            A =   A_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,4)).*STD_A(Temp_Index)';
            
            % Beta is not treated probabilistically:
            Beta = Beta_at_Temp(Temp_Index)';
            
            % Alpah_SF, corrisponds to Parameter 7 in the LHS matrix
            Alpha_SF = (Alpha_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,7)).*(STD_Alpha))./ Alpha_at_Temp(Temp_Index)' ; 
            
            
            % Elastic stress range
            
            switch AnalysisType
                case 'Probabilistic'
                    Sigma_el = Simple_VM_Str_Range(Prob_SU_Strs{Tube,1}.*(ESF*ones(1,6)) .* (Alpha_SF*ones(1,6)),...
                        Prob_RT_Strs{Tube,1}.*(ESF*ones(1,6)) .* (Alpha_SF*ones(1,6)));
                case 'Deterministic'
                    Sigma_el = Simple_VM_Str_Range(Prob_SU_Strs{Tube,1}.*(ESF) .* (Alpha_SF),...
                        Prob_RT_Strs{Tube,1}.*(ESF) .* (Alpha_SF));
                    Sigma_el = median(Sigma_el);
            end
            
            
            S_old = 500; % The initaial guess in Newton-Raphson
            err = 100;
            
            while max(err) > 1/100
                Eqn = (S_old./(E_bar) + (S_old./A).^(1./Beta)).*S_old - Sigma_el.^2./E_bar;
                dEqn = S_old.*(1./E_bar + (S_old./A).^(1./Beta - 1)./(A.*Beta)) + (S_old./A).^(1./Beta) + S_old./E_bar;
                S_new = S_old - Eqn./dEqn;
                err = abs(S_new - S_old);
                S_old = S_new;
            end
            
            Sigma_ep = S_new;
            
            Varep_ep = Sigma_ep./(E_bar) + (Sigma_ep./A).^(1./Beta);
            
            Varep_p_CA = (Sigma_ep./A).^(1./Beta);
            
            
            Es = Sigma_ep./Varep_ep;
            nu_bar = nu.*(Es./E_bar) + 0.5.*(1-Es./E_bar);
            Kv = ((1+nu_bar).*(1-nu))./((1+nu).*(1-nu_bar));
            Varep_vol = (Kv-1).*Sigma_el./E_bar;
            
            Varep_T_reload = Varep_vol + Varep_ep;
            
            %% Reverse stress datum
            
            T_Hot = round(max([Prob_RT_Temps{Tube,1},SD_Temp,Prob_SU_Temps{Tube,1}],[],2),4, 'significant');
            T_Cold = round(min([Prob_RT_Temps{Tube,1},Prob_SU_Temps{Tube,1}],[],2),4, 'significant');
            
            Temp_Index_Hot = FindExtrapIndex(T_Hot,Extrap_Temps); % This find the indeies of Extrap_Temps corrisponding to the elements in T_Hot
            Temp_Index_Cold = FindExtrapIndex(T_Cold,Extrap_Temps);
            
            % Sy corrisponds to Parameter 5 in the LHS matrix
            Sy_Hot = Sy_at_Temp(Temp_Index_Hot)' + Normalised_Bins(LHS(:,5)).*STD_Sy(Temp_Index_Hot)';
            Sy_Cold = Sy_at_Temp(Temp_Index_Cold)' + Normalised_Bins(LHS(:,5)).*STD_Sy(Temp_Index_Cold)';
            
            % Ks is not treated probabilistically:
            Ks_Hot = Ks_at_Temp(Temp_Index_Hot); Ks_Hot = Ks_Hot';
            Ks_Cold = Ks_at_Temp(Temp_Index_Cold); Ks_Cold = Ks_Cold';
            
            KsSy_Range = Ks_Cold.*Sy_Cold + Ks_Hot.*Sy_Hot;
            
            Sigma_RD = zeros(size(KsSy_Range));
            P_Mask = (Sigma_ep > KsSy_Range);
            N_Mask = (Sigma_ep < KsSy_Range);
            
            Sigma_RD(P_Mask) = Sigma_ep(P_Mask)./2+ abs(Ks_Cold(P_Mask).*Sy_Cold(P_Mask) - Ks_Hot(P_Mask).*Sy_Hot(P_Mask))./2;
            Sigma_RD(N_Mask) =  Ks_Cold(N_Mask).*Sy_Cold(N_Mask);
            
            %% Find the stress at the beginning of the dwell
            
            C = 0; % This is a counter in case the next line files, and the dT distribution for the closest avaialbe tilt is to be used
            
            while isempty(dT_MetalTemp_Samples{Tube}{Tilts(Event_No)-9+C})
                C = C + 1;
            end
            
            Event_Temp = round(ones(Nb,1)*All_Temps(Event_No) + dT_MetalTemp_Samples{Tube}{Tilts(Event_No)-9+C}(Str_MetTemp_Perm),4, 'significant');
            
            
            AllCycleTemps = [AllCycleTemps,Event_Temp]; % Saving the prob temperatures for a single cycle
            
            % Material properties are taken at the hotter of the event temp OR the SU:
            T_MatPro = round(max([Event_Temp,Prob_SU_Temps{Tube,1}],[],2),4, 'significant');
            
            Temp_Index = FindExtrapIndex(T_MatPro,Extrap_Temps); % This find the indeies of Extrap_Temps corrisponding to the elements in T_Hot
            
            % E_bar corrisponds to Parameter 6 in the LHS matrix
            E_bar =   E_bar_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,6)).*(STD_E_Bar(Temp_Index)');
            
            % ESF - This has the same permutation as E_Bar, so the 6th colomn of LHS
            ESF = (E_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,6)).*(STD_E(Temp_Index)'))./E_at_Temp(Temp_Index)';
            
            % A corrisponds to Parameter 4 in the LHS matrix
            A =   A_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,4)).*STD_A(Temp_Index)';
            
            % Beta is not treated probabilistically, but still a function of temperature:
            Beta = Beta_at_Temp(Temp_Index);Beta = Beta';
            
            % Elastic stress range:
            
            switch AnalysisType
                case 'Probabilistic'
                    
                    Event_Stress_Comps = Prob_Str_Comps{Tube}{Tilts(Event_No)-9+C};
                    
                    SC = 2; % This is the dominant stress component
                    [~,I] = sort(Event_Stress_Comps(:,SC),'ascend');
                    
                    Event_Stress_Comps = Event_Stress_Comps(I,:); % Sort the stress compoents accoring to the most dominant component
                    
                    Event_Stress_Comps = Event_Stress_Comps(Str_MetTemp_Perm,:);  % Reshuffel the stresses again according to the predefined stress and temperature permutation for this cycle
                    
                    DomStrComp = Event_Stress_Comps(:,2);
                    
                    Event_Stress_Comps = Event_Stress_Comps.*(ESF*ones(1,6)) .* (Alpha_SF*ones(1,6));
                    
                    [UniDuct_S_Frac,Event_Sigma_H,Event_Sigma_1,Event_Sigma_VM,Flag_NoCreepDamage] = SpindlerFraction(Event_Stress_Comps);
                    
                    SigmaFrac_1_VM = Event_Sigma_1./Event_Sigma_VM;
                    SigmaFrac_H_VM = Event_Sigma_H./Event_Sigma_VM;
                    
                    Sigma_el = Simple_VM_Str_Range(Prob_SU_Strs{Tube,1}.*(ESF*ones(1,6)) .* (Alpha_SF*ones(1,6)),...
                        Event_Stress_Comps); % The -9 is becasue All_Str_Comps{Tube} is nubered 1:184 rather than 10:194
                    
                case 'Deterministic'
                    Event_Stress_Comps = Prob_Str_Comps{Tube}{Tilts(Event_No)-9+C};
                    
                    SC = 2; % This is the dominant stress component
                    [~,I] = sort(Event_Stress_Comps(:,SC),'ascend');
                    
                    Event_Stress_Comps = Event_Stress_Comps(I,:); % Sort the stress compoents accoring to the most dominant component
                    
                    Event_Stress_Comps = Event_Stress_Comps(LHS(:,15),:); % Choose the median accroding to the most dom stress component
                    
                    Event_Stress_Comps = Event_Stress_Comps.*(ESF*ones(1,6)) .* (Alpha_SF*ones(1,6));
                    
                    
                    [UniDuct_S_Frac,Event_Sigma_H,Event_Sigma_1,Event_Sigma_VM,Flag_NoCreepDamage] = SpindlerFraction(Event_Stress_Comps);
                    

                    SigmaFrac_1_VM = Event_Sigma_1./Event_Sigma_VM;
                    SigmaFrac_H_VM = Event_Sigma_H./Event_Sigma_VM;
                    
                    Sigma_el = Simple_VM_Str_Range(Prob_SU_Strs{Tube,1}.*(ESF) .* (Alpha_SF),...
                        Event_Stress_Comps); % The -9 is becasue All_Str_Comps{Tube} is nubered 1:184 rather than 10:194
                    
            end
            
            % Start of dwell stress calculation
            
            StressBeginningDwell = Solve_RambergOsgood(Sigma_el,SigmaRupRef,Sigma_RD,A,Beta,E_bar,Nb,AnalysisType);
            
            Sorted_StressBeginningDwell = sort(StressBeginningDwell);
                        
            % For a deterministic assessemnt, assign the median of Sigma_B
            switch AnalysisType
                case 'Deterministic'
                    StressBeginningDwell = Sorted_StressBeginningDwell(LHS(:,9));
            end
            
            %% Elastic-plastic stress and strain ranges :
            
            Sigma_ep = StressBeginningDwell + Sigma_RD;
            Varep_ep = (Sigma_RD + StressBeginningDwell)./(E_bar) + (StressBeginningDwell./A).^(1./Beta);
            
            Plastic_Strain = (StressBeginningDwell./A).^(1./Beta); % or Varep_ep - (StressBeginningDwell - (-Sigma_RD))./(E_bar), both give the same answer
            
            Varep_p_AB = Plastic_Strain;
            Varep_ep_AB = Varep_ep;
            
        else
            
            %% Find the stress at the beginning of the dwell for this new event
            
            switch AnalysisType
                case 'Probabilistic'
                    C = 0; % This is a counter in case the next line files, and the dT distribution for the closest avaialbe tilt is to be used
                    
                    while isempty(dT_MetalTemp_Samples{Tube}{Tilts(Event_No)-9+C})
                        C = C + 1;
                    end
                    
                    Event_Temp = round(ones(Nb,1)*All_Temps(Event_No) + dT_MetalTemp_Samples{Tube}{Tilts(Event_No)-9+C}(Str_MetTemp_Perm),4, 'significant');
                    
                    
                    % StressState1 = Prob_Str_Comps{Tube}{Tilts(Event_No-1)-9}(Str_MetTemp_Perm,:).*(ESF*ones(1,6)).* (Alpha_SF*ones(1,6)); % This is the previous event
                    StressState2 = Prob_Str_Comps{Tube}{Tilts(Event_No)-9+C}(Str_MetTemp_Perm,:).*(ESF*ones(1,6)).* (Alpha_SF*ones(1,6)); % This is the current event
                    
                case 'Deterministic'
                    Event_Temp = round(median(ones(Nb,1)*All_Temps(Event_No) + dT_MetalTemp_Samples{Tube}{Tilts(Event_No)-9}(Str_MetTemp_Perm)),4, 'significant');
                    
                    % StressState1 = Prob_Str_Comps{Tube}{Tilts(Event_No-1)-9}(Str_MetTemp_Perm,:).*(ESF).* (Alpha_SF); % This is the previous event
                    StressState2 = Prob_Str_Comps{Tube}{Tilts(Event_No)-9}(Str_MetTemp_Perm,:).*(ESF).* (Alpha_SF); % This is the current event
            end
            
            AllCycleTemps = [AllCycleTemps,Event_Temp]; % Saving the prob temperatures for a single cycle
            
            Event_Stress_Comps = StressState2;
            
            % Calculating the stress fractions at the start of each
            % event and then keep them fixed for the entire duration of
            % the dwellf for this event.
            
            [UniDuct_S_Frac,Event_Sigma_H,Event_Sigma_1,Event_Sigma_VM,Flag_NoCreepDamage] = SpindlerFraction(Event_Stress_Comps);
            
            
            switch AnalysisType
                case 'Probabilistic'
                    SigmaFrac_1_VM = Event_Sigma_1./Event_Sigma_VM;
                    SigmaFrac_H_VM = Event_Sigma_H./Event_Sigma_VM;
                    
                case 'Deterministic'
                    SigmaFrac_1_VM = median(Event_Sigma_1./Event_Sigma_VM);
                    SigmaFrac_H_VM = median(Event_Sigma_H./Event_Sigma_VM);
                    UniDuct_S_Frac = median(UniDuct_S_Frac);
            end
            
            
            CreepStressDropPerEvent = StressBeginningDwell - StressEndDwell; % This is the creep stress drop from the previous event
            
            % Calculating the new sigma_b by reloading or unloading
            
            Temp_Index = FindExtrapIndex(Event_Temp ,Extrap_Temps); % This find the indeies of Extrap_Temps corrisponding to the elements in T_Hot
            
            % E_bar corrisponds to Parameter 6 in the LHS matrix
            E_bar =   E_bar_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,6)).*(STD_E_Bar(Temp_Index)');
            
            % ESF - This has the same permutation as E_Bar, so the 6th colomn of LHS
            ESF = (E_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,6)).*(STD_E(Temp_Index)'))./E_at_Temp(Temp_Index)';
            
            % A corrisponds to Parameter 4 in the LHS matrix
            A =   A_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,4)).*STD_A(Temp_Index)';
            
            % Beta is not treated probabilistically:
            Beta = Beta_at_Temp(Temp_Index);Beta = Beta';
            
            % Calculate the stress range for new event
            switch AnalysisType
                case 'Probabilistic'
                    Sigma_el_B_plus1_A = Simple_VM_Str_Range(Prob_SU_Strs{Tube,1}.*(ESF*ones(1,6)) .* (Alpha_SF*ones(1,6)),...
                        StressState2);
                case 'Deterministic'
                    Sigma_el_B_plus1_A = Simple_VM_Str_Range(Prob_SU_Strs{Tube,1}.*(ESF) .* (Alpha_SF),...
                        StressState2);
            end
            
            % Ramberg-Osgood + Neuber first
            
            Sigma_B_plus1 = Solve_RambergOsgood(Sigma_el_B_plus1_A,SigmaRupRef,Sigma_RD,A,Beta,E_bar,Nb,AnalysisType);  % Sigma_RD is from the first event for this cycle
            
            Sigma_B_plus1 = Sigma_B_plus1 - CreepStressDropPerEvent; % The new stress range is the stress range for this event minus the stress drop from the previous event
            
            
            %%%%%%%%%%%%%%%%%%% Validation %%%%%%%%%%%%%%%%%%%%%%%%
            
            % If you look at this histogram, for the same tilt
            % Sigma_B_plus1 and StressEndDwell should give the same
            % answer. But not quite. This can be explained by
            % Sigma_B_plus1 being based on material properties
            % caluclated at a different temperature to the Sigma_B_1
            % from the previous event. This is becasue two events with
            % the same tilt can have different tube temperatures
            
            %                     Change_in_Tilt = (Tilts(Event_No) - Tilts(Event_No-1));
            %
            %                     if Change_in_Tilt == 0
            %                         figure; histogram(Sigma_B_plus1 - StressEndDwell)
            %                         xlabel(['Change in dwell stress given a ' num2str(Change_in_Tilt) '�C tilt change' ])
            %                         close(gcf)
            %                     end
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
            StressBeginningDwell = Sigma_B_plus1;
            
            Sorted_StressBeginningDwell = sort(StressBeginningDwell);
            
            switch AnalysisType
                case 'Probabilistic'
                    StressBeginningDwell = Sorted_StressBeginningDwell(Str_MetTemp_Perm);
                case 'Deterministic'
                    StressBeginningDwell = Sorted_StressBeginningDwell(LHS(:,9));
            end
            
        end
        
        
        StressBeginningDwell(StressBeginningDwell<SigmaRupRef) = SigmaRupRef; % Don't allow the stress to go below the ref stress
        

        %%  RELAXATION ALGORITHEM
        
        %% Step 1 defining the initial conditions depending if this is a new cycle
        
        Creep_Strain_Increment = ones(Nbb,1).*DefultStrainIncrement;
        
        switch PR_Options
            
            case 'Zeta_P'
                if CycleEventNo(Event_No) == 1 % This is the first event of the cycle
                    Creep_Strain = Creep_Strain_Increment;
                    Dwell_Stress = StressBeginningDwell;
                    CycleStartStress = StressBeginningDwell; % This is taken at the first event for a cycle and is needed for the fatigue damage later
                    if Event_No == 1 % This is the first event of the entire simulated history
                        Creep_Damage = zeros(Nbb,1);
                        Zeta_P = zeros(Nbb,1);
                        Varep_p_DC = zeros(Nbb,1);
                        Accumlated_creep_strain = Creep_Strain_Increment; % Just for the first event of the simulated history
                    else
                        Creep_Damage = EndCreepDamage;
                        Varep_pp_SPD = Varep_p_DC + Varep_p_CA + Varep_p_AB;
                        Zeta_P = 10.^(Zeta_Mean + Zeta_STD.*Normalised_Bins(LHS(:,3)) - 0.005./Varep_pp_SPD);
                        Zeta_P(Zeta_P>1) = 1; % Capping Zeta_P at 1
                        Accumlated_creep_strain = Accumlated_creep_strain + EndCreepStrain;
                    end
                else
                    
                    Creep_Strain = EndCreepStrain;
                    Dwell_Stress = StressBeginningDwell;
                    Creep_Damage = EndCreepDamage;
                    
                    Varep_pp_SPD = Varep_p_DC + Varep_p_CA + Varep_p_AB;
                    Zeta_P = 10.^(Zeta_Mean + Zeta_STD.*Normalised_Bins(LHS(:,3)) - 0.005./Varep_pp_SPD);
                    Zeta_P(Zeta_P>1) = 1; % Capping Zeta_P at 1
                    Accumlated_creep_strain = Accumlated_creep_strain  + EndCreepStrain;
                    
                end
                
            case 'PR'
                if CycleEventNo(Event_No) == 1 % This is the first event of the cycle
                    Creep_Strain = Creep_Strain_Increment;
                    Dwell_Stress = StressBeginningDwell;
                    CycleStartStress = StressBeginningDwell; % This is taken at the first event for a cycle and is needed for the fatigue damage later
                    if Event_No == 1 % This is the first event of the entire simulated history
                        Creep_Damage = zeros(Nbb,1);
                    else
                        Creep_Damage = EndCreepDamage;
                    end
                else
                    
                    Creep_Strain = EndCreepStrain;
                    Dwell_Stress = StressBeginningDwell;
                    CycleStartStress = StressBeginningDwell; % This is taken at the first event for a cycle and is needed for the fatigue damage later
                    Creep_Damage = EndCreepDamage;
                end
                Varep_pp_SPD = [];
                Zeta_P = [];
                Accumlated_creep_strain = [];
                
            case 'CH'
                
                if CycleEventNo(Event_No) == 1 % This is the first event of the cycle
                    
                    Dwell_Stress = StressBeginningDwell;
                    CycleStartStress = StressBeginningDwell; % This is taken at the first event for a cycle and is needed for the fatigue damage later
                    if Event_No == 1 % This is the first event of the entire simulated history
                        Creep_Strain = Creep_Strain_Increment;
                        Creep_Damage = zeros(Nbb,1);
                    else
                        Creep_Strain = EndCreepStrain;
                        Creep_Damage = EndCreepDamage;
                    end
                else
                    
                    Creep_Strain = EndCreepStrain;
                    Dwell_Stress = StressBeginningDwell;
                    CycleStartStress = StressBeginningDwell; % This is taken at the first event for a cycle and is needed for the fatigue damage later
                    Creep_Damage = EndCreepDamage;
                end
                Varep_pp_SPD = [];
                Zeta_P = [];
                Accumlated_creep_strain = [];
                
        end
        
        
        % Save the initial creep strain at the start of the cycle
        if CycleEventNo(Event_No) == 1
            Initial_Cycle_Creep_Strain = Creep_Strain;
            Initial_Cycle_Stress = Dwell_Stress;
        end
        

        
        t_dwell = ones(Nbb,1).*Dwell_Times(Event_No);
        Int_Time_Resolution = t_dwell*(Int_Time_Resolution_Factor);
        
        Dwell_Stress_Rate = zeros(Nbb,1);
        
        while   sum(t_dwell > Int_Time_Resolution) ~= 0
            %% Step 2: calculate the creep strain rate based on chosen constitutive model (in this case HTBASS)
            % Probabilistic HTBASS:
            [Creep_Strain_Rate,Creep_Strain_Rate_Ref] = Prob_Creep_Rate(Creep_Strain,Plastic_Strain,Zeta_P,Accumlated_creep_strain,Dwell_Stress,SigmaRupRef,Event_Temp,Normalised_Bins,LHS(:,2),PR_Options);
            
            %% Step 3: calculate the time increment
            dt = Creep_Strain_Increment./ Creep_Strain_Rate;
            
            %% Step 4.a: calcualte the remaining creep dwell
            
            %%%%%%%%%%%%%%% Original code %%%%%%%%%%%%%%%%%%%%%%%%%%
            Mask = dt < t_dwell; % compare this time interval with the remaining creep dwell and adjust the strain increment if needed
            t_dwell(Mask) = t_dwell(Mask) - dt(Mask);

            %% Step 5.a: new creep strain and dwell stress

            Creep_Strain(Mask) = Creep_Strain(Mask) + Creep_Strain_Increment(Mask);
            Dwell_Stress_Rate(Mask) = -(E_bar(Mask)./Z(Mask)).*(Creep_Strain_Rate(Mask)-Creep_Strain_Rate_Ref(Mask));
            Dwell_Stress_Rate(Dwell_Stress_Rate>0) = 0; % The creep rate can't be positive during a dwell, the stress can't increase spontaniously
            Dwell_Stress(Mask) = Dwell_Stress(Mask) + dt(Mask).*Dwell_Stress_Rate(Mask);
            
            
            %% Step 5.0: Estimating the value of Z 
            StressDrop = StressBeginningDwell - Dwell_Stress;
            Z = (2-(StressDrop./StressBeginningDwell))./(1-(StressDrop./StressBeginningDwell));
            
            %% Step 6.a: Ductility and creep damage
            
            % Note: if Event_Sigma_H are Event_Sigma_1 used these are
            % assumed to be constant during the dwell for the moment, which of course is not the case in reality
            
            Varep_f_SMDE = Prob_Varep_f(Dwell_Stress,...
                SigmaFrac_1_VM,...
                SigmaFrac_H_VM,...
                Creep_Strain_Rate,...
                Event_Temp,...
                Normalised_Bins,...
                LHS(:,1),...
                UniDuct_S_Frac,...
                Flag_NoCreepDamage,...
                ConfLimit,...
                ConfFactor,...
                AnalysisType);
            
            
            %% Need to account for the trails which are compressive (given by Flag_NoCreepDamage).
            % These do not incurr an increase of creep damage
            
            Flag_NoCreepDamage = (Varep_f_SMDE==inf);
            
            DamageMask = logical(Mask.*(~Flag_NoCreepDamage));
            
            Creep_Damage(DamageMask) = Creep_Damage(DamageMask)  + (dt(DamageMask) .*Creep_Strain_Rate(DamageMask))./(Varep_f_SMDE(DamageMask));
            
            %% Step 4-6.b: Deal with the time increments that overshot
            if sum(~Mask)~=0
                Creep_Strain_Increment(~Mask) = Creep_Strain_Increment(~Mask) .*t_dwell(~Mask)./dt(~Mask).*0.95;
            end

            
            
        end
        

        %% Sensitivy per event
        
        EventCreepDamageIncrement = Creep_Damage - EndCreepDamage;
        
        DuctilityMask = Varep_f_SMDE~=inf;
        
        if Nb <= 1000
            try
                for SC = 1:6
                    SO_Stress_SA_Per_Event(Event_No,SC) = ...
                        corr(EventCreepDamageIncrement(DuctilityMask),Event_Stress_Comps(DuctilityMask,SC),'type',CorrType);
                end
                
                SO_Temp_SA_Per_Event(Event_No,1) = ...
                    corr(EventCreepDamageIncrement(DuctilityMask),Event_Temp(DuctilityMask),'type',CorrType);
                
                SO_Sigma_B_SA_Per_Event(Event_No,1) = ...
                    corr(EventCreepDamageIncrement(DuctilityMask),StressBeginningDwell(DuctilityMask),'type',CorrType);
                
            catch
                SO_Stress_SA_Per_Event(Event_No,:) = [0 0 0 0 0 0];
                SO_Temp_SA_Per_Event(Event_No,1) = 0;
                SO_Sigma_B_SA_Per_Event(Event_No,1) = 0;
            end
            
        elseif Nb > 1000
            
            SO_Stress_SA_Per_Event = [];
            SO_Temp_SA_Per_Event = [];
            SO_Sigma_B_SA_Per_Event = [];
            
        end
        
        
        %% Save creep damages & strains for this event to be used as the start for the following event
        
        EndCreepDamage = Creep_Damage;
        StressEndDwell = Dwell_Stress;
        EndCreepStrain = Creep_Strain;
        
        
        if Nb <= 1000
            
            Sor_Creep_Strain = sort(Creep_Strain);
            Sor_Creep_Damage = sort(Creep_Damage);
            Sor_Creep_Strain_Rate = sort(Creep_Strain_Rate);
            Sort_Dwell_Stress = sort(Dwell_Stress);
            Sort_Sigma_B = sort(StressBeginningDwell);
            
            switch AnalysisType
                case 'Probabilistic'
                    
                    EndEventCreepStrain(Event_No,:) = [min(Sor_Creep_Strain) Sor_Creep_Strain(Nb*0.025) median(Sor_Creep_Strain) Sor_Creep_Strain(Nb*0.975)  max(Sor_Creep_Strain)];
                    EndEventCreepDamage(Event_No,:) = [min(Sor_Creep_Damage) Sor_Creep_Damage(Nb*0.025) median(Sor_Creep_Damage) Sor_Creep_Damage(Nb*0.975)  max(Sor_Creep_Damage)];
                    EndEventCreepRate(Event_No,:) = [min(Sor_Creep_Strain_Rate) Sor_Creep_Strain_Rate(Nb*0.025) median(Sor_Creep_Strain_Rate) Sor_Creep_Strain_Rate(Nb*0.975)  max(Sor_Creep_Strain_Rate)];
                    EndEventDwellStress(Event_No,:) = [min(Sort_Dwell_Stress) Sort_Dwell_Stress(Nb*0.025) median(Sort_Dwell_Stress) Sort_Dwell_Stress(Nb*0.975) max(Sort_Dwell_Stress)];
                    StartEventDwellStress(Event_No,:) = [min(Sort_Sigma_B) Sort_Sigma_B(Nb*0.025) median(Sort_Sigma_B) Sort_Sigma_B(Nb*0.975) max(Sort_Sigma_B)];
                case 'Deterministic'
                    EndEventCreepStrain(Event_No,3) = Creep_Strain;
                    EndEventCreepDamage(Event_No,3) = Creep_Damage;
                    EndEventCreepRate(Event_No,3) = Creep_Strain_Rate;
                    EndEventDwellStress(Event_No,3) = Dwell_Stress;
                    StartEventDwellStress(Event_No,3) = StressBeginningDwell;
            end
            
        end
        
        
    else
        
        %% Small check:
        if EndCycleEvents_Indicies(Cycle_Counter)+1 ~= Event_No
            disp('Error in cycles/events sequence!!!')
        end
        
        % Now, before starting a new cycle, calculate the total strain range for the half
        % cycle with creep dwell and then the fatigue damage
        
        %% Reloading after creep dwell: onstruction from the end of the creep dwell
        
        
        % If a cycle ends, then the drop is from the start of dwell stress
        % of the first event (recorded before hand) and the stress at
        % the end of the last event (which is simply Dwell_Stress at this
        % point):
        
        CycleStressDrop =  CycleStartStress - StressEndDwell;
        
        
        % Max half cycle temperature for material properties and fatigue
        % damage. This is taken as the temperature of the maximum
        % temprature event for a specific cycle:
        
        
        MaxCycleTemp = max(AllCycleTemps,[],2);
        
        Temp_Index = FindExtrapIndex(MaxCycleTemp ,Extrap_Temps); % This find the indeies of Extrap_Temps corrisponding to the elements in T_Hot
        
        % E_bar corrisponds to Parameter 6 in the LHS matrix
        E_bar =   E_bar_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,6)).*(STD_E_Bar(Temp_Index)');
        
        % ESF - This has the same permutation as E_Bar, so the 6th colomn of LHS
        ESF = (E_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,6)).*(STD_E(Temp_Index)'))./E_at_Temp(Temp_Index)';
        
        % A corrisponds to Parameter 4 in the LHS matrix
        A =   A_at_Temp(Temp_Index)' + Normalised_Bins(LHS(:,4)).*STD_A(Temp_Index)';
        
        % Beta is not treated probabilistically:
        Beta = Beta_at_Temp(Temp_Index);Beta = Beta';
        
        % Calculate the stress range for this half cycle
        switch AnalysisType
            case 'Probabilistic'
                Sigma_el_CA = Simple_VM_Str_Range(Prob_SU_Strs{Tube,1}.*(ESF*ones(1,6)) .* (Alpha_SF*ones(1,6)),...
                    Prob_RT_Strs{Tube,1}.*(ESF*ones(1,6)) .* (Alpha_SF*ones(1,6)));
            case 'Deterministic'
                Sigma_el_CA = Simple_VM_Str_Range(Prob_SU_Strs{Tube,1}.*(ESF) .* (Alpha_SF),...
                    Prob_RT_Strs{Tube,1}.*(ESF) .* (Alpha_SF));
        end
        
        
        Sigma_el_AC = Sigma_el_CA - CycleStressDrop;
        
        Sigma_F = Solve_RambergOsgood(Sigma_el_AC,SigmaRupRef,Sigma_RD,A,Beta,E_bar,Nb,AnalysisType);  % Sigma_RD is from the first event for this cycle
        
        switch AnalysisType
            case 'Deterministic'
                Sigma_F  =  median(Sigma_F);
        end
        
        
        Sigma_ep = Sigma_F + Sigma_RD;
        
        Varep_ep = ((Sigma_RD + Sigma_F)./(E_bar) + (2.*Sigma_F./A).^(1./Beta));
        
        Es = Sigma_ep./Varep_ep;
        nu_bar = nu.*(Es./E_bar) + 0.5.*(1-Es./E_bar);
        Kv = ((1+nu_bar).*(1-nu))./((1+nu).*(1-nu_bar));
        
        Varep_vol = (Kv-1).*Sigma_el_AC./E_bar;
        
        % Find the total creep increment for this cycle
        
        CycleCreepIncrement = EndCreepStrain - Initial_Cycle_Creep_Strain;
        
        Varep_T_load = Varep_ep + Varep_vol + ...%
            (CycleCreepIncrement - CycleStressDrop./E_bar);
        
        Sigma_ep_DC = abs(Sigma_F - StressEndDwell);
        Varep_ep_DC = (abs(Sigma_F - StressEndDwell)./(E_bar) + (2.*Sigma_F./A).^(1./Beta));
        
        Varep_p_DC = (2.*Sigma_F./A).^(1./Beta);
        
        %% Calculate the fatigue damage per cycle
        
        switch AnalysisType
            case 'Probabilistic'
                Fatigue_Varep_T = max([Varep_T_load, Varep_T_reload],[],2);
            case 'Deterministic'
                Fatigue_Varep_T = max([median(Varep_T_load), Varep_T_reload],[],2);
        end
        
        Fatigue_Damage = Fatigue_Damage + FatigueDamage_V2(Fatigue_Varep_T,MaxCycleTemp,ConfFactor,Normalised_Bins,LHS(:,8));
        
        
        %% Tracking the total damage per cycle
        TotalDamage_By_Cycle{Cycle_Counter} = Fatigue_Damage + Creep_Damage; % This is accumulated damage
        
        Increment_of_TotalDamge_By_Cycle = TotalDamage_By_Cycle{Cycle_Counter} - Initial_TotalDamage_By_Cycle;
        
        Initial_TotalDamage_By_Cycle = TotalDamage_By_Cycle{Cycle_Counter}; % Initial as in at the start of the next cycle
        
        
        %% SA: Calcualting correlations between the increment of total damage by cycle and each material property
        
        switch AnalysisType
            case 'Probabilistic'
                if Nb <= 1000
                    [SA_Indicies(Cycle_Counter,:),CovMat{Cycle_Counter}] = Cycle_Corr_SA(Varep_f_SMDE,Increment_of_TotalDamge_By_Cycle,LHS,...
                        StressBeginningDwell,DomStrComp,Event_Temp,Prob_SU_Strs,Prob_RT_Strs,Prob_RT_Temps,Prob_SU_Temps,...
                        Tube,Cycle_Counter,CorrType);
                elseif Nb > 1000
                    SA_Indicies = [];
                    CovMat = [];
                end
            case 'Deterministic'
                SA_Indicies = [];
        end
        
        %% Calculating the probability of failure as a fuction of time
        
        Prob_Fail(Cycle_Counter) = sum(TotalDamage_By_Cycle{Cycle_Counter}>1)./Nb;
        
        Mean_Log_Damage(Cycle_Counter) = mean(log10(TotalDamage_By_Cycle{Cycle_Counter}));
        STD_Log_Damage(Cycle_Counter) = std(log10(TotalDamage_By_Cycle{Cycle_Counter}));
        
        Total_Strain_Range(Cycle_Counter) = median(Fatigue_Varep_T);
        
        
        %% Update the cycle counter:
        Cycle_Counter = Cycle_Counter + 1;
       
        AllCycleTemps = []; % Clearing this for a new cycle
        
        %% reshuffle the permutation for SO stresses and metal temperatures
        % after every cycle:
        rng('shuffle');
        Str_MetTemp_Perm = randperm(Nb);
        
        
        %% reshuffle the permutation for the transients for the coming cycle. 
        
        % Check if this is a reactor or boiler cycle:

        if sum(Cycle_Counter == BoilerCyles)
            
            switch AnalysisType
                case 'Probabilistic'
                    
                    % Resuffle and apply BC factors 
                    
                    rng('shuffle');
                    SU_RandPerm = randperm(Nb)';% Keep the same permutation for stresses and temperatures
                    Prob_SU_Strs{Tube,1} = SU_Strs_Samples{Tube,1}(SU_RandPerm,:).*RC_Str_Factor;
                    Prob_SU_Temps{Tube,1} = ones(size(SU_Temps_Samples{Tube,1})).*RC_Temp;
                    
                    RT_RandPerm = SU_RandPerm ; % For RTs use the same perm
                    Prob_RT_Strs{Tube,1} = RT_Strs_Samples{Tube,1}(RT_RandPerm,:).*BT_Str_Factor;
                    Prob_RT_Temps{Tube,1} = ones(size(RT_Temps_Samples{Tube,1})).*BT_Temp;
                    
                    
                case 'Deterministic'
                    
                    % Apply BC factors 
                    
                    Prob_SU_Strs{Tube,1} = SU_Strs_Samples{Tube,1}.*RC_Str_Factor;
                    Prob_SU_Temps{Tube,1} = RC_Temp;
                    
                    Prob_RT_Strs{Tube,1} = RT_Strs_Samples{Tube,1}.*BT_Str_Factor;
                    Prob_RT_Temps{Tube,1} = BT_Temp;
            end
            
        else
            switch AnalysisType
                case 'Probabilistic'
                    
                    % Resuffle only
                    
                    rng('shuffle');
                    SU_RandPerm = randperm(Nb)';% Keep the same permutation for stresses and temperatures
                    Prob_SU_Strs{Tube,1} = SU_Strs_Samples{Tube,1}(SU_RandPerm,:);
                    Prob_SU_Temps{Tube,1} = SU_Temps_Samples{Tube,1}(SU_RandPerm);
                    
                    RT_RandPerm = SU_RandPerm ; % For RTs use the same perm
                    Prob_RT_Strs{Tube,1} = RT_Strs_Samples{Tube,1}(RT_RandPerm,:);
                    Prob_RT_Temps{Tube,1} = RT_Temps_Samples{Tube,1}(RT_RandPerm);
              
                 case 'Deterministic'
                    
                    % Apply BC factors 
                    
                    Prob_SU_Strs{Tube,1} = SU_Strs_Samples{Tube,1};
                    Prob_SU_Temps{Tube,1} = RC_Temp;
                    
                    Prob_RT_Strs{Tube,1} = RT_Strs_Samples{Tube,1};
                    Prob_RT_Temps{Tube,1} = BT_Temp;
                    
                    
            end
        end
    end
    
   disp(['Tube: ' num2str(Tube) ' // Completed (%): ' num2str( round(100*Event_No./length(Dwell_Times),3))]);

end

TotalDamage = Fatigue_Damage + Creep_Damage;
End_Prob_Fail = sum(TotalDamage>1)./Nb;

SO_Stress_SA.SO_Stress_SA_Per_Event = SO_Stress_SA_Per_Event;
SO_Stress_SA.SO_Temp_SA_Per_Event = SO_Temp_SA_Per_Event;
SO_Stress_SA.SO_Sigma_B_SA_Per_Event = SO_Sigma_B_SA_Per_Event;

memory

end


function PrepareWorkSpace(Asmt_Sets_Filename,WorkSpace_Filename)

load(Asmt_Sets_Filename)

%% Defult confidnece limits for most parameters
ConfLimit = 0.95;
ConfFactors = norminv([(1-ConfLimit)/2 1-(1-ConfLimit)/2]);
ConfFactor = (ConfFactors(2)-ConfFactors(1))/2;

%% Reading the processed input plant data for the probabilistic assessment
[ArrayInputData,Dwell_Times,Modes,CycleEventNo,Tilts] = PrepareHistoryData(Repeat_History_Data_Analysis);

%% Find the bins for a standard normal distribution
Normalised_Bins = NormDist_LHS_Bins(Nb);

%% Deterministic inputs
Z = ones(Nb,1).*3;

nu = 0.29; % Possion's ratio
Sy_CoV =  Sy_R66_Max_CoV(ConfFactor); % CoV for proof stress

%% Temperature extrapolated inputs
Extrap_Temps = [20, 300:0.1:650]; % The temperatures to consturcting a lookup table for material properties
[E_bar_at_Temp,E_at_Temp] = Elastic_Properties_Lookup(Extrap_Temps);
[A_at_Temp,Beta_at_Temp] = Cyclic_Properties_Lookup(Extrap_Temps);
[Sy_at_Temp,Ks_at_Temp] = Tensile_Properties_Lookup(Extrap_Temps);
Alpha_at_Temp = Thermal_Expansion_Lookup(Extrap_Temps);

%% Zeta_P factor for primary rest
[Zeta_Mean,Zeta_STD] = DefineZetaP(ConfFactor);

%% Count the number of samples cycles within the given history

CycleNo = sum(Dwell_Times==0); % Total number of cycels
EndCycleEvents_Indicies = find(Dwell_Times==0)-1;
StartCycleEvents_Indicies = [1; find(Dwell_Times(1:end-1)==0)+1];

CycleTotalDwellDuraction = zeros(CycleNo,1);

for C = 1:CycleNo
    CycleTotalDwellDuraction(C,1) = sum(Dwell_Times(StartCycleEvents_Indicies(C):EndCycleEvents_Indicies(C)));
end

%% Inputs from previous assessment
SigmaRupRef = 20;  % Rupture Reference Stress page 37 of M.Stenvens Report
SD_Temp = 20;  % Assumed shutdown temperature

switch AnalysisType
    case 'Probabilistic'
        SD_Temp = ones(Nb,1).*SD_Temp; % Shut-down temperature
end

%% # Input  : Loading data for uncertainty in metal temperature when compred with steam temperature
% this is loaded here, but the associated permutations are done inside the history loop

dT_MetalTemp_Samples = PrepareMetalTempSamples(Nb,Plot_SS_Temp_Histograms);


%% # Input 4: Probabilsitic Ramberg-Osgood's A (sized Nb X 1 for a single temperature)
STD_A = A_at_Temp*0.25./ConfFactor;

%% # Input 5: Probabilistic proof stress (sized Nb X 1 for a single temperature)
STD_Sy = Sy_at_Temp.*Sy_CoV;

%% # Input 6: Probabilisic Modified Young's Modulus (sized Nb X 1 for a single temperature)

% 10 GPa is the difference between the mean and lower bound on E.
% Thus this expression covertes this into a STD on E_bar:

CoV_E = 10/158.5; % This is the CoV at 550�C. Assume the CoV is constant for all temps

STD_E = CoV_E.*E_bar_at_Temp; % This is in MPa
STD_E_Bar = (3./(2*(1+0.3)))./ConfFactor.*(STD_E);  % This is assumed to be temperature independent

%% # Input 9: Probabilistic coefficient of thermal expansion (Alpha)

Uncertainty_Alpha = 1.4e-6; % R66, Section 2, Figure 2.35

STD_Alpha = Uncertainty_Alpha./ConfFactor;

%% # Input  : Probabilistic TRANSIENT stresses (should be 6 SCs, each sized Nb X CycleNo)

Trans_SS_Stress_Comp_Order = [2 3 1 6 4 5]; % This is to account for the fact that two differernt FE models were used to get transient & SS stresses

if Repeat_Transient_Sampling
    Transient_Stress_and_Temp_Sampling(Trans_SS_Stress_Comp_Order,Nb,CycleNo);
end

save(WorkSpace_Filename); % This is to be later used by each individual worker in the parallel pool


end



%% Scripts for fitting distributions

function Ductility_Characterisation(Data)

MLE_Resutls = UoB_DistFitter_MLE(Data,[]);

LRM_Resutls = UoB_DistFitter_LRM(Data,[]);


end

function Resutls = UoB_DistFitter_MLE(Data,Dist_Option)

format short;

Data = sort(Data(:));

%% Structures and preallocations
Distributions = {   'Lognormal' ...
    'Normal'...
    '3-P Lognormal' ...
    'Weibull' ...
    '3-P Weibull'...
    'ExtremeValue' ...
    'GeneralizedExtremeValue'...
    'Exponential'...
    '2-P Exponential'};

No_Dist = length(Distributions) ;
LocalResutls = cell(No_Dist,1);

% Specifying the which distributions to be used
Dist_Choise = strcmp(Dist_Option,Distributions);
I = find(Dist_Choise~=0);

if isempty(I)
    Dist_Choise = 1:length(Distributions);
else
    Dist_Choise = I;
end

DistType = Distributions(Dist_Choise);

Mean_P_Values = zeros(No_Dist,1);
Min_P_Values = zeros(No_Dist,1);

% Calculating the frequencies of each data point
x_med = Data;
fi = ones(size(x_med));

% Cumulative Frequencies
f_cum_i = cumsum(fi);

% Ranking equation
Fi = (f_cum_i-0.3)/(length(Data)+0.4); %Median Rank - used with Weibull


for i = 1:length(DistType)% going through each distribution
    switch  DistType{i}
        case 'Lognormal'
            %% Log-Normal
            
            % Fitting a probability distribution, and creating a probaiblity distribution
            % object to conduct the Chi^2, K-S and A-D tests.
            
            pd = fitdist(Data,'Lognormal');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data,pd);
            
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            Lambda = pd.mu;
            Alpha = pd.sigma;
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = log(x_med);
            y_points = norminv(Fi,0,1);
            
            % Calcualting R_Squared
            R_Squared =  corr(x_points,y_points)^2;
            
            % Saving the info for this particual attempt
            LocalResutls{i}.DistName = 'Lognormal';
            LocalResutls{i}.ParamDisc = {'Lamda' 'Alpha'};
            LocalResutls{i}.Params = [Lambda  Alpha];
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = (exp(Alpha^2)-1)^0.5;
            [Eq_Mu,Eq_STD]  = Lognormal_Equ_Normal(Lambda,Alpha);
            LocalResutls{i}.Eq_Normal_Params =  [Eq_Mu Eq_STD];
            LocalResutls{i}.Eq_Normal_CoV = Eq_STD./Eq_Mu;
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
        case 'Normal'
            %% Normal
            
            % Fitting a probability distribution, and creating a probaiblity distribution
            % object to conduct the Chi^2, K-S and A-D tests.
            
            pd = fitdist(Data,'Normal');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data,pd);
            
            % Saving info about the Pvals for comparing the fits later
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            Mean = pd.mu;
            STD = pd.sigma;
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = x_med;
            y_points = norminv(Fi,0,1);
            
            % Calcualting R_Squared
            R_Squared =  corr(x_points,y_points)^2;
            
            % Saving the info for this particual attempt
            LocalResutls{i}.DistName = 'Normal';
            LocalResutls{i}.ParamDisc = {'Mean' 'STD'};
            LocalResutls{i}.Params = [Mean  STD];
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = STD./Mean;
            LocalResutls{i}.Eq_Normal_Params = [Mean  STD];
            LocalResutls{i}.Eq_Normal_CoV = STD./Mean;
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
        case '3-P Lognormal'
            
            %% 3P Log-Normal
            
            % Finding the optimum value for the minimum value x_0
            x_0 = 0:0.0001:(min(Data)-0.001);
            
            Pval = zeros(length(x_0),1);
            
            for MV = 1:length(x_0)
                pd = fitdist(Data-x_0(MV),'Lognormal');
                [~,Ps]= Goodness_of_Fit_3_Tests(Data-x_0(MV),pd);
                Pval(MV) = mean(Ps);
            end
            
            x_0_Opt = x_0(Pval==max(Pval));
            
            % Fitting a probability distribution, and creating a probaiblity distribution
            % object to conduct the Chi^2, K-S and A-D tests.
            
            pd = fitdist(Data-x_0_Opt,'Lognormal');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data-x_0_Opt,pd);
            
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            Lambda = pd.mu;
            Alpha = pd.sigma;
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = log(x_med-x_0_Opt);
            y_points = norminv(Fi,0,1);
            
            % Calcualting R_Squared
            R_Squared =  corr(x_points,y_points)^2;
            
            % Saving the info for this particual attempt
            LocalResutls{i}.DistName = '3-P Lognormal';
            LocalResutls{i}.ParamDisc = {'Lamda' 'Alpha' 'Minimum Value'};
            LocalResutls{i}.Params = [Lambda  Alpha x_0_Opt];
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = (exp(Lambda+0.5*Alpha^2)*(exp(Alpha^2)-1)^0.5)/(x_0_Opt + exp(Lambda+0.5*Alpha^2));
            LocalResutls{i}.Eq_Normal_Params = 'N/A';
            LocalResutls{i}.Eq_Normal_CoV = 'N/A';
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
        case 'Weibull'
            %% Weibull
            
            % Fitting a probability distribution, and creating a probaiblity distribution
            % object to conduct the Chi^2, K-S and A-D tests.
            
            pd = fitdist(Data,'Weibull');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data,pd);
            
            % Saving info about the Pvals for comparing the fits later
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            Theta   = pd.a;
            Beta = pd.b;
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = log(x_med);
            y_points = log(log(1./(1-Fi)));
            
            % Calcualting R_Squared
            R_Squared =  corr(x_points,y_points)^2;
            
            % Saving the info for this particual attempt
            LocalResutls{i}.DistName = 'Weibull';
            LocalResutls{i}.ParamDisc = {'Theta(Characteristic)' 'Beta(Shape)'};
            LocalResutls{i}.Params = [Theta  Beta];
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = ((gamma(1+2/Beta))/(gamma(1+1/Beta)^2) - 1)^0.5;
            [Eq_Mu,Eq_STD]  = Two_P_Weibull_Equ_Normal(Theta,Beta);
            LocalResutls{i}.Eq_Normal_Params = [Eq_Mu Eq_STD];
            LocalResutls{i}.Eq_Normal_CoV = Eq_STD./Eq_Mu;
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
        case '3-P Weibull'
            %% 3-P Weibull
            
            % Finding the optimum value for the minimum value x_0
            x_0 = 0:0.0001:(min(Data)-0.001);
            
            Pval = zeros(length(x_0),1);
            
            for MV = 1:length(x_0)
                pd = fitdist(Data-x_0(MV),'Weibull');
                [~,Ps]= Goodness_of_Fit_3_Tests(Data-x_0(MV),pd);
                Pval(isnan(Pval)) = 0;
                Pval(MV) = mean(Ps);
            end
            
            x_0_Opt = x_0(Pval==max(Pval));
            
            x_0_Opt = x_0_Opt(1);
            
            pd = fitdist(Data-x_0_Opt ,'Weibull');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data-x_0_Opt,pd);
            
            % Saving info about the Pvals for comparing the fits later
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            Theta   = pd.a;
            Beta = pd.b;
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = log(x_med-x_0_Opt);
            y_points = log(log(1./(1-Fi)));
            
            % Calcualting R_Squared
            R_Squared =  corr(x_points,y_points)^2;
            
            % Saving discription of distribution
            LocalResutls{i}.DistName = '3-P Weibull';
            LocalResutls{i}.ParamDisc = {'Theta(Characteristic)' 'Beta(Shape)' 'x_0(Expected Min Value)'};
            LocalResutls{i}.Params = [Theta  Beta x_0_Opt];
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = ((gamma(1+2/Beta))/(gamma(1+1/Beta)^2) - 1)^0.5;
            [Eq_Mu,Eq_STD]  = Three_P_Weibull_Equ_Normal(Theta,Beta,x_0_Opt);
            LocalResutls{i}.Eq_Normal_Params = [Eq_Mu Eq_STD];
            LocalResutls{i}.Eq_Normal_CoV = Eq_STD./Eq_Mu;
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
        case 'ExtremeValue'
            %% ExtremeValue
            
            pd = fitdist(Data,'ExtremeValue');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data,pd);
            
            % Saving info about the Pvals for comparing the fits later
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = x_med;
            y_points = log(log(1./(1-Fi)));
            
            % Calcualting R_Squared
            R_Squared =  corr(x_points,y_points)^2;
            
            % Saving discription of distribution
            LocalResutls{i}.DistName = 'ExtremeValue';
            LocalResutls{i}.ParamDisc = {'mu (Location)' 'sigma (Scale)' };
            LocalResutls{i}.Params = [pd.mu pd.sigma];
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = 'N/A';
            LocalResutls{i}.Eq_Normal_Params = 'N/A';
            LocalResutls{i}.Eq_Normal_CoV = 'N/A';
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
        case 'GeneralizedExtremeValue'
            %% GeneralizedExtremeValue
            
            pd = fitdist(Data,'GeneralizedExtremeValue');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data,pd);
            
            % Saving info about the Pvals for comparing the fits later
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = 'N/A';
            y_points = 'N/A';
            
            % Calcualting R_Squared
            R_Squared =  'N/A'; %corr(x_points,y_points)^2;
            
            % Saving discription of distribution
            LocalResutls{i}.DistName = 'GeneralizedExtremeValue';
            LocalResutls{i}.ParamDisc = {'k (Shape)' 'sigma (Scale)' 'mu (Location)'};
            LocalResutls{i}.Params = [pd.k pd.sigma pd.mu];
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = 'N/A';
            LocalResutls{i}.Eq_Normal_Params = 'N/A';
            LocalResutls{i}.Eq_Normal_CoV = 'N/A';
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
        case 'Exponential'
            %% Exponential
            
            pd = fitdist(Data,'Exponential');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data,pd);
            
            % Saving info about the Pvals for comparing the fits later
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = x_med;
            y_points = log(1./(1-Fi));
            
            % Calcualting R_Squared
            R_Squared =  corr(x_points,y_points)^2;
            
            % Saving discription of distribution
            LocalResutls{i}.DistName = 'Exponential';
            LocalResutls{i}.ParamDisc = {'Mean (mu)'};
            LocalResutls{i}.Params = pd.mu;
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = 'N/A';
            LocalResutls{i}.Eq_Normal_Params = 'N/A';
            LocalResutls{i}.Eq_Normal_CoV = 'N/A';
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
        case '2-P Exponential'
            
            %% Two parameter Exponential
            
            % Finding the optimum value for the minimum value x_0
            x_0 = 0:0.0001:(min(Data)-0.001);
            
            Pval = zeros(length(x_0),1);
            
            for MV = 1:length(x_0)
                pd = fitdist(Data-x_0(MV),'Exponential');
                [~,Ps]= Goodness_of_Fit_3_Tests(Data-x_0(MV),pd);
                Pval(isnan(Pval)) = 0;
                Pval(MV) = mean(Ps);
            end
            
            x_0_Opt = x_0(Pval==max(Pval));
            
            x_0_Opt = x_0_Opt(1);
            
            
            pd = fitdist(Data-x_0_Opt,'Exponential');
            
            % Conducting the tests
            [GoF_Results,Pvals] = Goodness_of_Fit_3_Tests(Data-x_0_Opt,pd);
            
            % Saving info about the Pvals for comparing the fits later
            Mean_P_Values(i) = mean(Pvals);
            Min_P_Values(i) = min(Pvals);
            
            % Creating points for probability plot (this is for validation purposes)
            x_points = x_med;
            y_points = log(1./(1-Fi));
            
            % Calcualting R_Squared
            R_Squared =  corr(x_points,y_points)^2;
            
            % Saving discription of distribution
            LocalResutls{i}.DistName = 'Exponential';
            LocalResutls{i}.ParamDisc = {'Mean (mu)' 'Min Value (x_0)'};
            LocalResutls{i}.Params = [pd.mu x_0_Opt];
            LocalResutls{i}.pd = pd;
            LocalResutls{i}.CoV = 'N/A';
            LocalResutls{i}.Eq_Normal_Params = 'N/A';
            LocalResutls{i}.Eq_Normal_CoV = 'N/A';
            LocalResutls{i}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
            LocalResutls{i}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
            LocalResutls{i}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
            LocalResutls{i}.ProbabilityPlotData = [x_points y_points];
            LocalResutls{i}.R_Sqaured = R_Squared;
            
            
    end
end




%% Finding best distribution based on R^2

[Dist_Ind,Rank_Ind] = find(Mean_P_Values==max(max(Mean_P_Values)));
Mean_P_Values(isnan(Mean_P_Values)) = 0;
[~,Dist_Order_P_Values] = sort(Mean_P_Values,'ascend');
Dist_Order_P_Values = Distributions(flip(Dist_Order_P_Values))';
Max_P_Values_by_NoBins = max(max(Mean_P_Values));


%% Saving the final results
Resutls.FittingMethod = 'Maximum Likelihood';
Resutls.SampleSize = length(Data);
Resutls.DistName = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.DistName;
Resutls.DistParamsDisc = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.ParamDisc;
Resutls.DistParams = [LocalResutls{Dist_Ind(1),Rank_Ind(1)}.Params];
Resutls.pd = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.pd;
Resutls.CoV = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.CoV;
Resutls.EqNormal_Params = [LocalResutls{Dist_Ind(1),Rank_Ind(1)}.Eq_Normal_Params];
Resutls.Eq_Normal_CoV = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.Eq_Normal_CoV;
Resutls.Mean_P_Val = Mean_P_Values(Dist_Ind(1),Rank_Ind(1));
Resutls.Distribution_Rank = Dist_Order_P_Values ;
Resutls.ChiSqd_Test_Hypothesis = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.ChiSqd_Test_Hypothesis;
Resutls.KS_Test_Hypothesis = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.KS_Test_Hypothesis;
Resutls.AD_Test_Hypothesis = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.AD_Test_Hypothesis;
Resutls.ProbabilityPlotData = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.ProbabilityPlotData;
Resutls.R_Sqaured  = LocalResutls{Dist_Ind(1),Rank_Ind(1)}.R_Sqaured;




% %% Probability Plot
% figure;whitebg('w'); set(gcf,'color','w');
% plot(Resutls.ProbabilityPlotData(:,1), Resutls.ProbabilityPlotData(:,2),'ok','MarkerSize',6,'MarkerFaceColor','k'); legend([Resutls.DistName ' - R^2 = ' num2str(Resutls.R_Sqaured)]); hold on;
%
% xlabel('Linearised data'); ylabel('Linearised CDF')
%
% X = min(Resutls.ProbabilityPlotData(:,1)):0.01:max(Resutls.ProbabilityPlotData(:,1));
% P = polyfit(Resutls.ProbabilityPlotData(:,1),Resutls.ProbabilityPlotData(:,2),1);
% Y  = polyval(P,X);
%
% gcf; plot(X,Y,'--r','LineWidth',2)
%
% set(gca,'FontSize',12,'fontWeight','bold');
% set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
% set(gca,'LineWidth',2);

end

function Resutls = UoB_DistFitter_LRM(Data,Dist_Option)

format short;

Data = sort(Data(:));

%% Finding the number of bins

N = length(Data);
Data_sorted = sort(Data);
Q1 = median(Data_sorted(1:N/2));
Q3 = median(Data_sorted(N/2+1:end));
NoBins = round([1+3.22*log10(N)...
    N^0.5 ...
    ((max(Data)-min(Data))*N^(1/3))./(2*(Q3-Q1))]);

NoBins = 11;


%% Structures and preallocations
Distributions = {   'Lognormal' ...
    'Normal'...
    '3-P Lognormal' ...
    'Weibull' ...
    '3-P Weibull' ...
    'Maximum Extreme Value Type I  (Gumbel Distribution)'...
    'ExtremeValue'...
    'Maximum Extreme Value Type II  (Frechet Distribution)' ...
    'Exponential' ...
    '2-P Exponential'};

No_Dist = length(Distributions) ;
x = cell(1,No_Dist);
x_med = cell(1,No_Dist);
f = cell(1,No_Dist);
f_cum = cell(1,No_Dist);
Fi_Large = cell(1,No_Dist);
Fi_Hazen = cell(1,No_Dist);
Fi_Mean = cell(1,No_Dist);
Fi_Median = cell(1,No_Dist);
Fi_AnyDist = cell(1,No_Dist);
Fi_Extreme = cell(1,No_Dist);
Fi_Normal = cell(1,No_Dist);
Fi = cell(1,No_Dist);
Rank_Equations = {'Hazen' 'Mean' 'Median' 'Approx_any_distribution' 'Extreme Type 1' 'Approx_for_Normal'};
% R_Squared = zeros(No_Dist,length(Rank_Equations));
LocalResutls = cell(1,No_Dist);

R_3PW = zeros(1,1000);

% Specifying the which distributions to be used
Dist_Choise = strcmp(Dist_Option,Distributions);
I = find(Dist_Choise~=0);

if isempty(I)
    Dist_Choise = 1:length(Distributions);
else
    Dist_Choise = I;
end

DistType = Distributions(Dist_Choise);


for k = 1:length(NoBins)
    for i = 1:length(DistType)% going through each distribution
        
        %         if N > 30 % Constructing a histogram
        %             % The class limits
        %             x{i} = linspace(min(Data),max(Data),NoBins(k)+1)';
        %             % The mid rang values
        %             x_med{i} = x{i}+mean(diff(x{i}))./2;
        %             x_med{i} = x_med{i}(1:end-1);
        %             % The Frequencies
        %             f{i} = histc(Data,[x{i}(1)-1;x{i}(2:end-1);x{i}(end)+1]); f{i}  = f{i}(1:end-1);
        %         else
        %             x_med{i} = Data;
        %             f{i} = ones(size(x_med{i}));
        %             NoBins(k) = N;
        %         end
        
        x_med{i} = Data;
        f{i} = ones(size(x_med{i}));
        NoBins(k) = N;
        
        % Cumulative Frequencies
        f_cum{i} = cumsum(f{i});
        
        % Ranking equations
        Fi_Large{i} =  f_cum{i}./N; % For very large samples
        Fi_Hazen{i} = (f_cum{i}-0.5)./N; % Hazen Formula - commonly used in engineering
        Fi_Mean{i} = f_cum{i}/(N+1); %Mean Rank - used with small samples
        Fi_Median{i} = (f_cum{i}-0.3)/(N+0.4); %Median Rank - used with Weibull
        Fi_AnyDist{i} = (f_cum{i}-0.4)/(N+0.2); % a reasonable approxiamtion for any distribution
        Fi_Extreme{i} = (f_cum{i}-0.35)/(N); % used with Extreme Value Type I
        Fi_Normal{i} = (f_cum{i}-0.3175)/(N+0.365); % reasonable approxiamtion for Normal distribution
        
        
        Fi{i} = {Fi_Hazen{i} Fi_Mean{i} Fi_Median{i} Fi_AnyDist{i} Fi_Extreme{i} Fi_Normal{i}} ;
        
        
        for j = 1:length(Fi{i}) % Going through each ranking equation
            switch  DistType{i}
                case 'Lognormal'
                    %% Log-Normal
                    x_points = log(x_med{i});
                    y_points = norminv(Fi{i}{j},0,1);
                    % Distribuiton parameters
                    R = Scatter(x_points,y_points);
                    A_0 = R.Intercept;
                    A_1 = R.Gradient;
                    Lambda = -(A_0/A_1);
                    Alpha = ((1-A_0)/A_1)+(A_0/A_1);
                    
                    % R_Squared
                    R_Squared{k}(i,j) =  R.R_Squared;
                    
                    % Creat a probability distribution object to conduct the
                    % Chi^2, K-S and A-D tests.
                    
                    pd = makedist(DistType{i},'mu',Lambda, 'sigma',Alpha);
                    
                    % Conducting the tests
                    GoF_Results = Goodness_of_Fit_3_Tests(Data,pd);
                    
                    % Saving the info for this particual attempt
                    LocalResutls{k}{i,j}.DistName = 'Lognormal';
                    LocalResutls{k}{i,j}.ParamDisc = {'Lamda' 'Alpha'};
                    LocalResutls{k}{i,j}.Params = [Lambda  Alpha];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = (exp(Alpha^2)-1)^0.5;
                    [Eq_Mu,Eq_STD]  = Lognormal_Equ_Normal(Lambda,Alpha);
                    LocalResutls{k}{i,j}.Eq_Normal_Params =  [Eq_Mu Eq_STD];
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = Eq_STD./Eq_Mu;
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case 'Normal'
                    %% Normal
                    x_points = x_med{i};
                    y_points = norminv(Fi{i}{j},0,1);
                    
                    % Distribuiton parameters
                    R = Scatter(x_points,y_points);
                    A_0 = R.Intercept;
                    A_1 = R.Gradient;
                    Mean = -(A_0/A_1);
                    STD = ((1-A_0)/A_1)+(A_0/A_1);
                    % R_Squared
                    R_Squared{k}(i,j) =  R.R_Squared;
                    
                    % Creat a probability distribution object to conduct the
                    % Chi^2, K-S and A-D tests.
                    
                    pd = makedist(DistType{i},'mu',Mean, 'sigma',STD);
                    
                    % Conducting the tests
                    GoF_Results = Goodness_of_Fit_3_Tests(Data,pd);
                    
                    % Saving the info for this particual attempt
                    LocalResutls{k}{i,j}.DistName = 'Normal';
                    LocalResutls{k}{i,j}.ParamDisc = {'Mean' 'STD'};
                    LocalResutls{k}{i,j}.Params = [Mean  STD];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = STD./Mean;
                    LocalResutls{k}{i,j}.Eq_Normal_Params = [Mean  STD];
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = STD./Mean;
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case '3-P Lognormal'
                    %% 3P Log-Normal
                    x_0 = 0:0.001:min(x_med{i});
                    
                    R_Squared_3PLN = zeros(length(x_0),1);
                    
                    for W = 1:length(x_0) % fining the R2 for an array of x_0
                        
                        x_0_W = ones(size(x_med{i}))*x_0(W);
                        x_points = log(x_med{i}-x_0_W);
                        y_points = norminv(Fi{i}{j},0,1);
                        % Distribuiton parameters
                        R = Scatter(x_points,y_points);
                        A_0(W) = R.Intercept;
                        A_1(W) = R.Gradient;
                        
                        if isnan(A_0(W)) || isnan(A_1(W))
                            R_Squared_3PLN(W,1) = 0;
                        else
                            R_Squared_3PLN(W,1) = R.R_Squared;
                        end
                        
                    end
                    
                    %R_Squared
                    [R_Squared{k}(i,j),Ind_Max_R] = max(R_Squared_3PLN(imag(R_Squared_3PLN)==0));
                    x_0_Opt = x_0(Ind_Max_R);
                    
                    x_points = log(x_med{i}-x_0_Opt);
                    y_points = norminv(Fi{i}{j},0,1);
                    
                    A_0 = A_0(Ind_Max_R);
                    A_1 = A_1(Ind_Max_R);
                    
                    Lambda = -(A_0/A_1);
                    Alpha = ((1-A_0)/A_1)+(A_0/A_1);
                    
                    % Creat a probability distribution object to conduct the
                    % Chi^2, K-S and A-D tests.
                    
                    pd = makedist('Lognormal','mu',Lambda, 'sigma',Alpha);
                    
                    GoF_Results = Goodness_of_Fit_3_Tests(Data-x_0_Opt,pd);
                    
                    % Saving the info for this particual attempt
                    LocalResutls{k}{i,j}.DistName = '3-P Lognormal';
                    LocalResutls{k}{i,j}.ParamDisc = {'Lamda' 'Alpha' 'Minimum Value'};
                    LocalResutls{k}{i,j}.Params = [Lambda  Alpha x_0_Opt];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = (exp(Lambda+0.5*Alpha^2)*(exp(Alpha^2)-1)^0.5)/(x_0_Opt + exp(Lambda+0.5*Alpha^2));
                    LocalResutls{k}{i,j}.Eq_Normal_Params = 'N/A';
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = 'N/A';
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case 'Weibull'
                    %% Weibull
                    x_points = log(x_med{i});
                    y_points = log(log(1./(1-Fi{i}{j})));
                    % Distribuiton parameters
                    R = Scatter(x_points,y_points);
                    A_0 = R.Intercept;
                    A_1 = R.Gradient;
                    Theta_LR = exp(-(A_0/A_1));
                    Beta_LR = A_1;
                    % R_Squared
                    R_Squared{k}(i,j) = R.R_Squared;
                    
                    % Creat a probability distribution object to conduct the
                    % Chi^2, K-S and A-D tests.
                    
                    pd = makedist(DistType{i},'a',Theta_LR, 'b',Beta_LR);
                    
                    % Conducting the tests
                    GoF_Results = Goodness_of_Fit_3_Tests(Data,pd);
                    
                    % Saving the info for this particual attempt
                    LocalResutls{k}{i,j}.DistName = 'Weibull';
                    LocalResutls{k}{i,j}.ParamDisc = {'Theta(Characteristic)' 'Beta(Shape)'};
                    LocalResutls{k}{i,j}.Params = [Theta_LR  Beta_LR];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = ((gamma(1+2/Beta_LR))/(gamma(1+1/Beta_LR)^2) - 1)^0.5;
                    [Eq_Mu,Eq_STD]  = Two_P_Weibull_Equ_Normal(Theta_LR,Beta_LR);
                    LocalResutls{k}{i,j}.Eq_Normal_Params = [Eq_Mu Eq_STD];
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = Eq_STD./Eq_Mu;
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case '3-P Weibull'
                    %% 3-P Weibull
                    
                    x_0 = 0:0.001:min(x_med{i});
                    
                    R_Squared_3PW = zeros(length(x_0),1);
                    
                    for W = 1:length(x_0) % fining the R2 for an array of x_0
                        
                        x_0_W = ones(size(x_med{i}))*x_0(W);
                        x_points = log(x_med{i}-x_0_W);
                        y_points = log(log(1./(1-Fi{i}{j})));
                        % Distribuiton parameters
                        R = Scatter(x_points,y_points);
                        A_0(W) = R.Intercept;
                        A_1(W) = R.Gradient;
                        
                        if isnan(A_0(W)) || isnan(A_1(W))
                            R_Squared_3PW(W) = 0;
                        else
                            R_Squared_3PW(W) = R.R_Squared;
                        end
                    end
                    
                    %R_Squared
                    [R_Squared{k}(i,j),Ind_Max_R] = max(R_Squared_3PW(imag(R_Squared_3PW)==0));
                    x_0_Opt = x_0(Ind_Max_R);
                    
                    x_points = log(x_med{i}-x_0_Opt);
                    y_points = log(log(1./(1-Fi{i}{j})));
                    
                    
                    A_0 = A_0(Ind_Max_R);
                    A_1 = A_1(Ind_Max_R);
                    
                    Theta = exp(-(A_0/A_1))+x_0_Opt;
                    Beta = A_1;
                    
                    
                    % Creat a probability distribution object to conduct the
                    % Chi^2, K-S and A-D tests.
                    
                    pd = makedist('Weibull','a',Theta, 'b',Beta);
                    
                    % Conducting the tests
                    GoF_Results = Goodness_of_Fit_3_Tests(Data-x_0_Opt,pd);
                    
                    % Saving discription of distribution
                    LocalResutls{k}{i,j}.DistName = '3-P Weibull';
                    LocalResutls{k}{i,j}.ParamDisc = {'Theta(Characteristic)' 'Beta(Shape)' 'x_0(Expected Min Value)'};
                    LocalResutls{k}{i,j}.Params = [Theta  Beta x_0_Opt];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = ((gamma(1+2/Beta))/(gamma(1+1/Beta)^2) - 1)^0.5;
                    [Eq_Mu,Eq_STD]  = Three_P_Weibull_Equ_Normal(Theta,Beta,x_0_Opt);
                    LocalResutls{k}{i,j}.Eq_Normal_Params = [Eq_Mu Eq_STD];
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = Eq_STD./Eq_Mu;
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case 'Maximum Extreme Value Type I  (Gumbel Distribution)'
                    %% Maximum Extreme Value Type I  (Gumbel Distribution)
                    x_points = x_med{i};
                    y_points = -log(log(1./(Fi{i}{j})));
                    % Distribuiton parameters
                    R = Scatter(x_points,y_points);
                    A_0 = R.Intercept;
                    A_1 = R.Gradient;
                    Theta = 1/A_1;
                    Nu = -(A_0/A_1);
                    % R_Squared
                    R_Squared{k}(i,j) = R.R_Squared;
                    % KS Testing for goodness-of-fit
                    u = [0:0.00001:0.999]';
                    x_fit = Nu - Theta.*log(log(1./(u)));
                    
                    % Saving discription of distribution
                    LocalResutls{k}{i,j}.DistName = 'Maximum Extreme Value Type I (Gumbel)';
                    LocalResutls{k}{i,j}.ParamDisc = {'Scale (Theta)' 'Lucation (Nu)'};
                    LocalResutls{k}{i,j}.Params = [Theta  Nu];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = 0;
                    [Eq_Mu,Eq_STD]  = Max_Ext_Value_TypeI_Equ_Normal(Theta,Nu);
                    LocalResutls{k}{i,j}.Eq_Normal_Params = [Eq_Mu Eq_STD];
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = Eq_STD./Eq_Mu;
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = 'N/A Under development';
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = 'N/A Under development';
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = 'N/A Under development';
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case 'ExtremeValue'
                    %% Minimum Extreme Value Type I
                    x_points = x_med{i};
                    y_points = log(log(1./(1-Fi{i}{j})));
                    % Distribuiton parameters
                    R = Scatter(x_points,y_points);
                    A_0 = R.Intercept;
                    A_1 = R.Gradient;
                    Theta = 1/A_1;
                    Nu = -(A_0/A_1);
                    % R_Squared
                    R_Squared{k}(i,j) = R.R_Squared;
                    
                    % Creat a probability distribution object to conduct the
                    % Chi^2, K-S and A-D tests.
                    
                    pd = makedist(DistType{i},'mu',Nu, 'sigma',Theta);
                    
                    % Conducting the tests
                    GoF_Results = Goodness_of_Fit_3_Tests(Data,pd);
                    
                    
                    % Saving discription of distribution
                    LocalResutls{k}{i,j}.DistName = 'Minimum Extreme Value Type I';
                    LocalResutls{k}{i,j}.ParamDisc = {'Scale (Theta)' 'Lucation (Nu)'};
                    LocalResutls{k}{i,j}.Params = [Theta  Nu];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = 0;
                    [Eq_Mu,Eq_STD]  = Min_Ext_Value_TypeI_Equ_Normal(Theta,Nu);
                    LocalResutls{k}{i,j}.Eq_Normal_Params = [Eq_Mu Eq_STD];
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = Eq_STD./Eq_Mu;
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case 'Maximum Extreme Value Type II  (Frechet Distribution)'
                    %% Maximum Extreme Value Type II  (Frechet Distribution)
                    x_points = log(x_med{i});
                    y_points = -log(log(1./(Fi{i}{j})));
                    % Distribuiton parameters
                    R = Scatter(x_points,y_points);
                    A_0 = R.Intercept;
                    A_1 = R.Gradient;
                    Sigma = exp(-A_0/A_1);
                    Lambda = A_1;
                    % R_Squared
                    R_Squared{k}(i,j) = R.R_Squared;
                    % KS Testing for goodness-of-fit
                    u = [0:0.001:0.999]';
                    x_fit = Sigma.*(log(1./u)).^(-1/Lambda);
                    
                    % Saving discription of distribution
                    LocalResutls{k}{i,j}.DistName = 'Maximum Extreme Value Type II (Frechet)';
                    LocalResutls{k}{i,j}.ParamDisc = {'Scale (Sigma)' 'Shape (Lambda)'};
                    LocalResutls{k}{i,j}.Params = [Sigma  Lambda];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = 'N/A';
                    LocalResutls{k}{i,j}.CoV = 'N/A';
                    LocalResutls{k}{i,j}.Eq_Normal_Params = 'N/A';
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = 'N/A';
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = 'N/A Under development';
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = 'N/A Under development';
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = 'N/A Under development';
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case 'Exponential'
                    
                    %% Exponential
                    x_points = x_med{i};
                    y_points = log(1./(1-Fi{i}{j}));
                    
                    % Distribuiton parameters
                    R = Scatter(x_points,y_points);
                    A_0 = R.Intercept;
                    A_1 = R.Gradient;
                    Theta_LR = 1/A_1;
                    
                    % R_Squared
                    R_Squared{k}(i,j) = R.R_Squared;
                    
                    % Creat a probability distribution object to conduct the
                    % Chi^2, K-S and A-D tests.
                    
                    pd = makedist(DistType{i},'mu',Theta_LR); % JB's book uses Theta but matlab uses Mu, they are the same thing in this case
                    
                    % Conducting the tests
                    GoF_Results = Goodness_of_Fit_3_Tests(Data,pd);
                    
                    % Saving discription of distribution
                    LocalResutls{k}{i,j}.DistName = 'Exponential';
                    LocalResutls{k}{i,j}.ParamDisc = {'Characteristic Value (Theta)'};
                    LocalResutls{k}{i,j}.Params = [Theta_LR];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = 'N/A';
                    LocalResutls{k}{i,j}.Eq_Normal_Params = 'N/A';
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = 'N/A';
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
                case '2-P Exponential'
                    %% Exponential
                    x_points = x_med{i};
                    y_points = log(1./(1-Fi{i}{j}));
                    
                    % Distribuiton parameters
                    R = Scatter(x_points,y_points);
                    A_0 = R.Intercept;
                    A_1 = R.Gradient;
                    Theta_LR = 1/A_1;
                    Mu_LR = -A_0*Theta_LR;
                    
                    % R_Squared
                    R_Squared{k}(i,j) = R.R_Squared;
                    
                    % Creat a probability distribution object to conduct the
                    % Chi^2, K-S and A-D tests.
                    
                    pd = makedist('Exponential','mu',Theta_LR); % JB's book uses Theta but matlab uses Mu, they are the same thing in this case
                    
                    % Conducting the tests
                    GoF_Results = Goodness_of_Fit_3_Tests(Data-Mu_LR,pd);
                    
                    % Saving discription of distribution
                    LocalResutls{k}{i,j}.DistName = '2-P Exponential';
                    LocalResutls{k}{i,j}.ParamDisc = {'Characteristic Value (Theta)' 'Minimum Value'};
                    LocalResutls{k}{i,j}.Params = [Theta_LR Mu_LR];
                    LocalResutls{k}{i,j}.CIs.Gradient = [R.Gradient_Lower_CI R.Gradient_Upper_CI];
                    LocalResutls{k}{i,j}.CIs.Intercept = [R.Intercept_Lower_CI R.Intercept_Upper_CI];
                    LocalResutls{k}{i,j}.pd = pd;
                    LocalResutls{k}{i,j}.CoV = 'N/A';
                    LocalResutls{k}{i,j}.Eq_Normal_Params = 'N/A';
                    LocalResutls{k}{i,j}.Eq_Normal_CoV = 'N/A';
                    LocalResutls{k}{i,j}.ChiSqd_Test_Hypothesis = GoF_Results.ChiSqd_Test_Hypothesis;
                    LocalResutls{k}{i,j}.KS_Test_Hypothesis = GoF_Results.KS_Test_Hypothesis;
                    LocalResutls{k}{i,j}.AD_Test_Hypothesis = GoF_Results.AD_Test_Hypothesis;
                    LocalResutls{k}{i,j}.ProbabilityPlotData = [x_points y_points];
                    
            end
        end
    end
end


%% Finding best distribution based on R^2

for k = 1:length(NoBins)
    
    [Dist_Ind{k},Rank_Ind{k}] = find(R_Squared{k}==max(max(R_Squared{k})));
    [~,Dist_Order_R_Squared] = sort(max(R_Squared{k},[],2));
    Dist_Order_R_Squared = Distributions(flip(Dist_Order_R_Squared))';
    Max_R_Squared_by_NoBins(k) = max(max(R_Squared{k}));
    
end

[~,K] = max(Max_R_Squared_by_NoBins);


%% Saving the final results

Resutls.FittingMethod = 'Linear Rectification';
Resutls.SampleSize = length(Data);
Resutls.DistName = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.DistName;
Resutls.DistParamsDisc = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.ParamDisc;
Resutls.DistParams = [LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.Params];
Resutls.CIs = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.CIs;
Resutls.pd = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.pd;
Resutls.CoV = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.CoV;
Resutls.EqNormal_Params = [LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.Eq_Normal_Params];
Resutls.Eq_Normal_CoV = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.Eq_Normal_CoV;
Resutls.R_Squared = max(max(R_Squared{K}));
Resutls.R = (max(max(R_Squared{K})))^0.5;
Resutls.NumberofBins = NoBins(K);
Resutls.RankEqn = Rank_Equations(Rank_Ind{K}(1));
Resutls.Distribution_Rank = Dist_Order_R_Squared ;
Resutls.ChiSqd_Test_Hypothesis = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.ChiSqd_Test_Hypothesis;
Resutls.KS_Test_Hypothesis = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.KS_Test_Hypothesis;
Resutls.AD_Test_Hypothesis = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.AD_Test_Hypothesis;
Resutls.ProbabilityPlotData = LocalResutls{K}{Dist_Ind{K}(1),Rank_Ind{K}(1)}.ProbabilityPlotData;


%% Probability Plot
figure;whitebg('w'); set(gcf,'color','w');
plot(Resutls.ProbabilityPlotData(:,1), Resutls.ProbabilityPlotData(:,2),'ok','MarkerSize',6,'MarkerFaceColor','k'); legend([Resutls.DistName ' - R^2 = ' num2str(Resutls.R_Squared)]); hold on;

xlabel('Linearised data'); ylabel('Linearised CDF')

X = min(Resutls.ProbabilityPlotData(:,1)):0.01:max(Resutls.ProbabilityPlotData(:,1));
P = polyfit(Resutls.ProbabilityPlotData(:,1),Resutls.ProbabilityPlotData(:,2),1);
Y  = polyval(P,X);

gcf; plot(X,Y,'--r','LineWidth',2)

set(gca,'FontSize',12,'fontWeight','bold');
set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
set(gca,'LineWidth',2);

end

function [GoF_Results,P_vals] = Goodness_of_Fit_3_Tests(Data,pd)

% 1. Chi^2Testing

[h,P_vals(1),~] = chi2gof(Data,'CDF',pd);

if h
    ChiSqd_Test_Hypothesis = {'Bad fit' };
else
    ChiSqd_Test_Hypothesis = {'Good fit' };
end


% 2. Kolmogorov-Smirnov testing

[h,P_vals(2),~,~] = kstest(Data,'CDF',pd);


if h
    KS_Test_Hypothesis = {'Bad fit'};
else
    KS_Test_Hypothesis = {'Good fit'};
end

% Anderson-Darling Testing

[h,P_vals(3)] = adtest(Data,'Distribution',pd);

if h
    AD_Test_Hypothesis = {'Bad fit' };
else
    AD_Test_Hypothesis = {'Good fit' };
end

GoF_Results.ChiSqd_Test_Hypothesis = ChiSqd_Test_Hypothesis;
GoF_Results.KS_Test_Hypothesis = KS_Test_Hypothesis;
GoF_Results.AD_Test_Hypothesis = KS_Test_Hypothesis;

end

function [Mu,STD] = Lognormal_Equ_Normal(lambda,alpha)
Mu = exp(lambda+(alpha^2)/2);
STD = (exp(2*lambda+2*(alpha^2))-exp(2*lambda+alpha^2)).^0.5;
end

function [Mu,STD] = Max_Ext_Value_TypeI_Equ_Normal(Theta,Nu)
Mu = Nu + 0.5772157*Theta;
STD = 1.2825498*Theta;
end

function [Mu,STD] = Min_Ext_Value_TypeI_Equ_Normal(Theta,Nu)
Mu = Nu - 0.5772157*Theta;
STD = 1.2825498*Theta;
end

function [Mu,STD] = Two_P_Weibull_Equ_Normal(Theta,Beta)
Mu = Theta*gamma(1+(1/Beta));
STD = Mu*Beta^(-0.926);
end

function [Mu,STD] = Three_P_Weibull_Equ_Normal(Theta,Beta,x_0)
Mu = x_0 + (Theta-x_0)*gamma(1+(1/Beta));
STD = (Mu-x_0)*Beta^(-0.926);
end

function [Results] = Scatter(x,y)

% x = [0.99 1.02 1.15 1.29 1.46 1.36 0.87 1.23 1.55 1.40 1.19 1.15 0.98 1.01 1.11 1.20 1.26 1.32 1.43 0.95]';
% y = [90.01 89.05 91.43 93.74 96.73 94.45 87.59 91.77 99.42 93.65 93.54 92.52 90.56 89.54 89.85 90.39 93.25 93.41 94.98 87.33]';

n = length(y);

Sxx = sum(x.^2) - (sum(x).^2)./n;
Sxy = sum(x.*y) - (sum(x)).*(sum(y))./(n);

% Least Squares estimate of the slope:
Beta_hat_1 = Sxy./Sxx;
% Least Squares estimate of the intercept:
Beta_hat_0 = mean(y)-Beta_hat_1.*mean(x);

% Thus the linear regression model is:
x_hat = (min(x)*0.90:(min(x)/5):max(x)*1.1)';
y_hat = Beta_hat_0 + Beta_hat_1.*x_hat;

% Residual Sum of Squares:
SSR = sum((y - (Beta_hat_0 + Beta_hat_1.*x)).^2);
% Total Sum of Squares
SST = sum((y - mean(y)).^2);
% Thus the variance and standard diviation of the error is:
Variance = SSR./(n-2);

% Standard errors
% 1. Standard error for gradient
Sigma_Squared = SSR/(n-2);
SE_Gradient  = (Sigma_Squared./Sxx).^0.5;
% 2. Standard error for intercept
SE_Intercept = (Sigma_Squared.*((1/n)+(mean(x).^2/Sxx))).^0.5;


% Confidence intervals for the gradient
alpha = 0.10;
ts = tinv([1-alpha/2],n-2);
Gradient_Upper_CI = Beta_hat_1 + ts.*SE_Gradient;
Gradient_Lower_CI = Beta_hat_1 - ts.*SE_Gradient;

% Confidence intervals for the intercept
alpha = 0.05;
ts = tinv([1-alpha/2],n-2);
Intercept_Upper_CI = Beta_hat_0 + ts.*SE_Intercept;
Intercept_Lower_CI = Beta_hat_0 - ts.*SE_Intercept;

% Summary of results
Results.SE_Gradient = SE_Gradient;
Results.SE_Intercept = SE_Intercept;
Results.R_Squared = 1 - SSR/SST;
Results.Gradient = Beta_hat_1;
Results.Gradient_Upper_CI = Beta_hat_1 + ts.*SE_Gradient;
Results.Gradient_Lower_CI = Beta_hat_1 - ts.*SE_Gradient;
Results.Intercept = Beta_hat_0;
Results.Intercept_Upper_CI = Intercept_Upper_CI;
Results.Intercept_Lower_CI = Intercept_Lower_CI;


end



function [X,PDF] = DistPlot(D,X_min,X_max)

X_min = floor(X_min);
X_max = ceil(X_max);
X_step = 0.001;


switch D.DistName
    case '3-P Weibull'
        Weibull_Dist = str2num(D.DistParams);
        Weibull_Theta = Weibull_Dist(1);
        Weibull_Beta = Weibull_Dist(2);
        Weibull_x_0 = Weibull_Dist(3);
        X = Weibull_x_0:X_step:X_max;
        PDF = (Weibull_Beta/(Weibull_Theta-Weibull_x_0)).*(((X-Weibull_x_0)./(Weibull_Theta-Weibull_x_0)).^(Weibull_Beta-1)).*exp(-((X-Weibull_x_0)./(Weibull_Theta-Weibull_x_0)).^Weibull_Beta);
        
    case 'Weibull'
        try
            Weibull_Dist = str2num(D.DistParams);
        catch
            Weibull_Dist = D.DistParams;
        end
        Weibull_Theta = Weibull_Dist(1);
        Weibull_Beta = Weibull_Dist(2);
        X = X_min:X_step:X_max;
        PDF = (Weibull_Beta/Weibull_Theta).*((X./Weibull_Theta).^(Weibull_Beta-1)).*exp(-(X./Weibull_Theta).^Weibull_Beta);
        
    case 'Normal'
        Normal_Dist = str2num(D.DistParams);
        Normal_Mean = Normal_Dist(1);
        Normal_STD = Normal_Dist(2);
        X = X_min:X_step:X_max;
        PDF = (1./(Normal_STD*(2.*pi).^0.5))*exp(-(X-Normal_Mean).^2/(2.*Normal_STD.^2));
        
    case 'LogNormal'
        try
            Lognormal_Dist = str2num(D.DistParams);
        catch
            Lognormal_Dist = D.DistParams;
        end
        Lognormal_Mean = Lognormal_Dist(1);
        Lognormal_Dispersion = Lognormal_Dist(2);
        X = X_min:X_step:X_max;
        PDF = (1./(X.*Lognormal_Dispersion.*(2.*pi).^0.5)).*exp(-(log(X)-Lognormal_Mean).^2/(2.*Lognormal_Dispersion.^2));
        
    case '3-P Lognormal'
        
        Lognormal_Dist = D.DistParams;
        Lognormal_Mean = Lognormal_Dist(1);
        Lognormal_Dispersion = Lognormal_Dist(2);
        Lognormal_Min = Lognormal_Dist(3);
        X = X_min:X_step:X_max;
        PDF = (1./((X-Lognormal_Min).*Lognormal_Dispersion.*(2.*pi).^0.5)).*exp(-(log((X-Lognormal_Min))-Lognormal_Mean).^2/(2.*Lognormal_Dispersion.^2));
        
end

try
    X = X(:);
    PDF = PDF(:)*mean(diff(X));
    
catch
    
    D.DistName
    
end

end

function [Varep_f,Param_1,Param_2] = Ductility_Samples(Varep_f_SMDE_BE,Varep_f_SMDE_LB,Varep_f_min,Dist_Type,ConfLimit,Normalised_Bins)

ConfLimit_Ind_LB = round((1-ConfLimit)/2*length(Normalised_Bins)); % Assuming the LB is the 2.5% lower percentaile
ConfLimit_Ind_BE = round(length(Normalised_Bins)/2); % Assuming the BE is the median of the 3P distribution


switch Dist_Type
    
    case '3-P Lognormal'
        
        % Step 1: Calculate the distribution parameters
        Alpha = (log(Varep_f_SMDE_BE - Varep_f_min) - log(Varep_f_SMDE_LB - Varep_f_min))./(round(Normalised_Bins(ConfLimit_Ind_BE)) - Normalised_Bins(ConfLimit_Ind_LB));
        Lamda = - Normalised_Bins(ConfLimit_Ind_LB).*Alpha  + log(Varep_f_SMDE_LB - Varep_f_min);
        
        
        % Step 2: Generate the samples based on the above estimates of the
        % distribution parameters and the LHS normal bins
        
        Varep_f = exp(Normalised_Bins.*Alpha + Lamda) + Varep_f_min;
        
        Param_1 = Alpha;
        Param_2 = Lamda;
        
        
    case '3-P Weibull'
        % Step 1: Calculate the distribution parameters
        Beta = [log((log(1-0.5))./log(1-0.025))]./log((Varep_f_SMDE_BE - Varep_f_min)./(Varep_f_SMDE_LB - Varep_f_min));
        Theta = Varep_f_min + (Varep_f_SMDE_BE - Varep_f_min)./((-log(1-0.5)).^(1./Beta));
        
        % Step 2: Generate the samples based on the above estimates of the
        % distribution parameters and the LHS normal bins
        Varep_f = Varep_f_min + (-log(1 - normcdf(Normalised_Bins))).^(1./Beta) .*(Theta - Varep_f_min);
        
        Param_1 = Beta;
        Param_2 = Theta;
        
end

end

function Normalised_Bins = NormDist_LHS_Bins(Nb)

Normal_Mean = 0;
Normal_STD = 1;

%% Defining the bins based on equal probabilities
Zeta = zeros(Nb+1,1);
P_cum_Zeta_I_minus_1 = zeros(Nb+1,1);
Mid_Bin_Value = zeros(Nb+1,1);
syms X
Normal_PDF = @(X) (1./(Normal_STD*(2.*pi).^0.5))*exp(-(X-Normal_Mean).^2/(2.*Normal_STD.^2));
Integral_fun = @(X) X.*((1./(Normal_STD*(2.*pi).^0.5))*exp(-(X-Normal_Mean).^2/(2.*Normal_STD.^2))); % This is the function to be integrated later

% Depending on the application, the bin may be defind based on
% all the range of probabilities from 0 to 1 or based on a
% slightly smaller range

P_cum_reduction = 0;
P_cum_upper = 1-P_cum_reduction;
P_cum_lower = 0+P_cum_reduction;

Prob_per_bin = (P_cum_upper - P_cum_lower)./Nb;

P_cum_Zeta_I_minus_1(1) = P_cum_lower;
P_cum_Zeta_I_minus_1(Nb+1) = P_cum_upper;
Zeta(1) = norminv(P_cum_Zeta_I_minus_1(1),Normal_Mean,Normal_STD);

for i = 2:Nb+1
    if P_cum_reduction == 0 && i == Nb+1
        Zeta(Nb+1) = Inf;
        P_cum_Zeta_I_minus_1(Nb+1) = normcdf(Zeta(Nb+1) ,Normal_Mean,Normal_STD);
        Mid_Bin_Value(Nb+1) = (1/Prob_per_bin)*(integral(Integral_fun,Zeta(Nb),inf));
    else
        Zeta(i) = norminv(P_cum_Zeta_I_minus_1(i-1)+Prob_per_bin,Normal_Mean,Normal_STD);
        P_cum_Zeta_I_minus_1(i) = normcdf(Zeta(i) ,Normal_Mean,Normal_STD);
        Mid_Bin_Value(i) = (1/Prob_per_bin)*(integral(Integral_fun,Zeta(i-1),Zeta(i)));
    end
end

Mid_Bin_Value = Mid_Bin_Value(Mid_Bin_Value~=0);

Normalised_Bins = Mid_Bin_Value;

end

function [Stats] = ChiSquared_Test(Data1,Data2,No_Bins)


Hist_Data1 = histogram(Data1,No_Bins);
Freq_Data1 = Hist_Data1.Values;

Hist_Data2 = histogram(Data2,No_Bins);
Freq_Data2 = Hist_Data2.Values;


Expected_Freq = Freq_Data1;
Oberved_Freq = Freq_Data2;

Chi_Sqrd = ((Oberved_Freq(Expected_Freq~=0) - Expected_Freq(Expected_Freq~=0)).^2)./Expected_Freq(Expected_Freq~=0);
Chi_Sqrd(isnan(Chi_Sqrd)) = [];
Stats.Chi_Sqrd = sum(Chi_Sqrd);


DOF = No_Bins-1;
Alpha = 0.05;
Stats.Chi2Critical = chi2inv(1-Alpha,DOF);


if  Chi_Sqrd < Stats.Chi2Critical
    Stats.Chi_Sqrd_Test_Results = 'Good fit';
else
    Stats.Chi_Sqrd_Test_Results = 'Not good fit';
end

Stats.DOF = DOF;
Stats.Alpha = Alpha;

end


%% Scripts for examining the bimodal distibution based on the PoF results from the assessment

function PlotBinomialDistribution(PoF_TPL,N_tot)


Range = 0:1:5;
Y_PDF = binopdf(Range,N_tot,PoF_TPL);
Y_CDF = binocdf(Range,N_tot,PoF_TPL);

figure; whitebg('w');set(gcf,'color','w');
plot(Range,Y_PDF,'--xk'); hold on;
plot(Range,Y_CDF,'-xk')

[hAx,hLine1,hLine2] = plotyy(Range,Y_PDF,Range,Y_CDF);

hLine1.LineStyle = '-';
hLine2.LineStyle = '--';

hLine1.Color = 'k';
hLine2.Color = 'k';

hAx(1).YColor = 'k';
hAx(2).YColor = 'k';

xlabel('Number of failed tubeplates accross fleet');
ylabel(hAx(1),'Binomial PDF'); % left y-axis
ylabel(hAx(2),'Binomial CDF'); % right y-axis

legend('PDF','CDF')

end


%% Script for SA based on correlations approach

function Percentage_Contribution_Corr = CorrSensitivitityAnalysis(SA_Tube,Tubes,SA_Indicies,CovMat,SO_Stress_SA,TotalDamage,LHS)


% Calculating the percentage contributions based on the median of the
% correlations for all cycles

Median_Correlations = [...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,1)),1)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,2)),2)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,2)),3)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,4)),4)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,5)),5)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,6)),6)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,7)),7)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,8)),8)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,9)),9)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,10)),10)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,11)),11)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,12)),12)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,13)),13)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,14)),14)),...
    median(SA_Indicies{find(Tubes==SA_Tube)}(~isnan(SA_Indicies{find(Tubes==SA_Tube)}(:,15)),15))];

Parameters_Discription = {'Ductility', 'Creep-rate','Zeta_P','A (RO)' ,'S_y','E', '\alpha','N_f','Sigma_B','SU Str','RT Str','SU Temp','RT Temp','SO Temp','SO Str'};


%% Normalise the percnetage contributions and sort them in order

Percentage_Contribution_Corr = abs(Median_Correlations)./sum(abs(Median_Correlations)); % Normalise to get acutal percentages

[~,Plotting_Order] = sort(Percentage_Contribution_Corr,'descend');

y =[Percentage_Contribution_Corr(Plotting_Order)];


%% Plotting the percentage contributions

figure; whitebg('w');set(gcf,'color','w');

B = bar(y*100);

set(B(1),'FaceColor',[150 150 150]./255,'LineWidth',1);

set(gca,'xticklabel',Parameters_Discription(Plotting_Order), 'TickLabelInterpreter', 'tex');

set(gca,'FontSize',12,'fontWeight','bold');
set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
set(gca,'LineWidth',2);

ylabel('SA Indicies (correlations based)','FontSize', 12);
xlabel('Input parameters','FontSize', 12);

set(gcf, 'Position', [100 100 1000 420]);

Direct = cd;
cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\11. Probabilistic Assessment\SA')
save(['SA_Corr_Based_Results' num2str(SA_Tube) '.mat'],'Median_Correlations','Parameters_Discription')
cd(Direct)


%% Looking at interdependencies between parameters

format short
No_Cycles = length(CovMat{find(Tubes==SA_Tube)});

Median_Covariance_Matrix = [];

TubeCovMatData = CovMat{find(Tubes==SA_Tube)};

for Param = 1:length(TubeCovMatData{1})
    
    Param_SA = [];
    
    for N = 1:No_Cycles
        Param_SA =  horzcat(Param_SA,   TubeCovMatData{N}(:,Param));
    end
    
    Param_SA(isnan(Param_SA)) = 0;
    
    MedianParam_SA = median(Param_SA,2);
    
    Median_Covariance_Matrix = horzcat(Median_Covariance_Matrix,round(MedianParam_SA,3));
    
end

Median_Covariance_Matrix =round(Median_Covariance_Matrix.*100,3);


end

function [SA_Indicies,CovMat] = Cycle_Corr_SA(Varep_f_SMDE,Increment_of_TotalDamge_By_Cycle,LHS,StressBeginningDwell,DomStrComp,Event_Temp,Prob_SU_Strs,Prob_RT_Strs,Prob_RT_Temps,Prob_SU_Temps,Tube,Cycle_Counter,CorrType)

DuctilityMask = Varep_f_SMDE~=inf;

SA_Output = Increment_of_TotalDamge_By_Cycle(DuctilityMask);

if sum(DuctilityMask) > 2
    
    
    SA_Indicies(1,1) = corr(SA_Output,LHS(DuctilityMask,1),'type',CorrType);
    SA_Indicies(1,2) = corr(SA_Output,LHS(DuctilityMask,2),'type',CorrType);
    SA_Indicies(1,3) = corr(SA_Output,LHS(DuctilityMask,3),'type',CorrType);
    SA_Indicies(1,4) = corr(SA_Output,LHS(DuctilityMask,4),'type',CorrType);
    SA_Indicies(1,5) = corr(SA_Output,LHS(DuctilityMask,5),'type',CorrType);
    SA_Indicies(1,6) = corr(SA_Output,LHS(DuctilityMask,6),'type',CorrType);
    SA_Indicies(1,7) = corr(SA_Output,LHS(DuctilityMask,7),'type',CorrType);
    SA_Indicies(1,8) = corr(SA_Output,LHS(DuctilityMask,8),'type',CorrType);
    
    SA_Indicies(1,9) = corr(SA_Output,StressBeginningDwell(DuctilityMask),'type',CorrType);
    
    SA_Indicies(1,10) = corr(SA_Output,Prob_SU_Strs{Tube,1}(DuctilityMask,2),'type',CorrType);
    SA_Indicies(1,11) = corr(SA_Output,Prob_RT_Strs{Tube,1}(DuctilityMask,2),'type',CorrType);
    
    SA_Indicies(1,12) = corr(SA_Output,Prob_SU_Temps{Tube,1}(DuctilityMask),'type',CorrType);
    SA_Indicies(1,13) = corr(SA_Output,Prob_RT_Temps{Tube,1}(DuctilityMask),'type',CorrType);
    
    
    SA_Indicies(1,14) = corr(SA_Output,Event_Temp(DuctilityMask),'type',CorrType);
    SA_Indicies(1,15) = corr(SA_Output,DomStrComp(DuctilityMask),'type',CorrType);
    
    
    All_Outputs = [SA_Output,...
        LHS(DuctilityMask,[1:8]),...
        StressBeginningDwell(DuctilityMask),...
        Prob_SU_Strs{Tube,1}(DuctilityMask,2),...
        Prob_RT_Strs{Tube,1}(DuctilityMask,2),...
        Prob_SU_Temps{Tube,1}(DuctilityMask),...
        Prob_RT_Temps{Tube,1}(DuctilityMask),...
        Event_Temp(DuctilityMask),...
        DomStrComp(DuctilityMask)];
    
    CovMat = corr(All_Outputs,'type',CorrType);
    
    
else
    
    SA_Indicies(1,1:15) = zeros(1,15);
    CovMat = zeros(16,16);
end

end


%% Scripts for preparation of transient stresses

function Transient_Stress_and_Temp_Sampling(Trans_SS_Stress_Comp_Order,Nb,CycleNo)

SU_StressLocation_Option = 'MaxStressLocation';
RT_StressLocation_Option = 'SU_Location';

% RT_StressLocation_Option = 'MinRangeLocation';

SU_Temp_Option = 'MinTemp';
RT_Temp_Option = 'MaxTemp';

for Trans_Tube = 1:10 % Only 10 becasue transients were analysised using a 1/6th model
    
    for C = 1:CycleNo
        Trans_SS_Stress_Comp_Order = [2 3 1 6 4 5]; % This is to account for the fact that two differernt FE models were used to get transient & SS stresses
        
        [Prob_SU_Strs_10_Tubes{Trans_Tube,C},Prob_SU_Temps_10_Tubes{Trans_Tube,C},...
            Det_SU_Strs{Trans_Tube,C},Det_SU_Temps{Trans_Tube,C}] = ...
            ProbTransStrComps(Trans_SS_Stress_Comp_Order,Nb,Trans_Tube,'SU',SU_StressLocation_Option,SU_Temp_Option);
        
        [Prob_RT_Strs_10_Tubes{Trans_Tube,C},Prob_RT_Temps_10_Tubes{Trans_Tube,C},...
            Det_RT_Strs{Trans_Tube,C},Det_RT_Temps{Trans_Tube,C}] = ...
            ProbTransStrComps(Trans_SS_Stress_Comp_Order,Nb,Trans_Tube,'RT',RT_StressLocation_Option,RT_Temp_Option); % More conservative option: 'MinRangeLocation'
        
        switch RT_StressLocation_Option
            case'SU_Location'
                
                Initial_RT_SU_Perm = [];
                
                Prob_RT_Strs_10_Tubes{Trans_Tube,C} = [];
                Prob_RT_Temps_10_Tubes{Trans_Tube,C} = [];
                Prob_SU_Strs_10_Tubes{Trans_Tube,C} = [];
                Prob_SU_Temps_10_Tubes{Trans_Tube,C} = [];
                
                for I_RT = 1:ceil(Nb/(length(Det_RT_Strs{Trans_Tube,C})))
                    for RT = 1:18
                        Initial_RT_SU_Perm = vertcat(Initial_RT_SU_Perm,[1:length(Det_SU_Strs{Trans_Tube,C})]');
                    end
                    Prob_RT_Strs_10_Tubes{Trans_Tube,C} = vertcat(Prob_RT_Strs_10_Tubes{Trans_Tube,C},Det_RT_Strs{Trans_Tube,C});
                    Prob_RT_Temps_10_Tubes{Trans_Tube,C} = vertcat(Prob_RT_Temps_10_Tubes{Trans_Tube,C},Det_RT_Temps{Trans_Tube,C});
                end
                
                RT_SU_Perm = randperm(Nb);
                
                Prob_RT_Strs_10_Tubes{Trans_Tube,C} = Prob_RT_Strs_10_Tubes{Trans_Tube,C}(RT_SU_Perm,Trans_SS_Stress_Comp_Order);
                Prob_RT_Temps_10_Tubes{Trans_Tube,C} = Prob_RT_Temps_10_Tubes{Trans_Tube,C}(RT_SU_Perm,:);
                Prob_SU_Strs_10_Tubes{Trans_Tube,C} = Det_SU_Strs{Trans_Tube,C}(Initial_RT_SU_Perm(RT_SU_Perm),Trans_SS_Stress_Comp_Order);
                Prob_SU_Temps_10_Tubes{Trans_Tube,C} = Det_SU_Temps{Trans_Tube,C}(Initial_RT_SU_Perm(RT_SU_Perm),:);
                
        end
        
        disp(['Sampling Transients: Tube = ' num2str(Trans_Tube) '// Cycle = ' num2str(C) ] )
    end
    
end

save(['Transient_Stress_Samples_10_Tubes_' num2str(Nb) '_Samples.mat'],'Prob_SU_Strs_10_Tubes','Prob_RT_Strs_10_Tubes','Prob_SU_Temps_10_Tubes','Prob_RT_Temps_10_Tubes','Det_SU_Strs','Det_SU_Temps','Det_RT_Strs','Det_RT_Temps')

end

function [Prob_SU_Strs,Prob_SU_Temps,Prob_RT_Strs,Prob_RT_Temps] = AssignCycleTransients(Nb,LHS,CycleNo,Tubes,Plot_Transient_Histograms,AnalysisType)

% Assign the transient samples based on how the tube configuration
% changes between the transient FE and the SS FE (the latter was a 1/6th model)

try
    load(['Transient_Stress_Samples_10_Tubes_' num2str(Nb) '_Samples.mat'])
catch
    if Nb < 10000
        load(['Transient_Stress_Samples_10_Tubes_' num2str(1000) '_Samples.mat'])
    else
        load(['Transient_Stress_Samples_10_Tubes_' num2str(10000) '_Samples.mat'])
    end
end



Transient_to_SS_Tube_Order = xlsread('Transient_Tube_Numbering.xlsx');
Transient_to_SS_Tube_Order = Transient_to_SS_Tube_Order(:,3);

CycleNo = 1; % Just do it for one cycle and then resuffle the same data at every cycle


for Tube = Tubes
    for C = 1:CycleNo
        
        No_Repeats = (Nb./length(Prob_SU_Strs_10_Tubes{Transient_to_SS_Tube_Order(Tube),C}));
        
        Prob_SU_Strs{Tube,C}  = repmat(   Prob_SU_Strs_10_Tubes{Transient_to_SS_Tube_Order(Tube),C},  No_Repeats, 1);
        Prob_SU_Temps{Tube,C} = repmat(   Prob_SU_Temps_10_Tubes{Transient_to_SS_Tube_Order(Tube),C}, No_Repeats, 1);
        Prob_RT_Strs{Tube,C}  = repmat(   Prob_RT_Strs_10_Tubes{Transient_to_SS_Tube_Order(Tube),C},  No_Repeats, 1);
        Prob_RT_Temps{Tube,C} = repmat(   Prob_RT_Temps_10_Tubes{Transient_to_SS_Tube_Order(Tube),C}, No_Repeats, 1);
    end
end

% Reshuffling the transient samples

for Tube = Tubes
    for C = 1:CycleNo
        switch AnalysisType
            case 'Probabilistic'
                SU_RandPerm = randperm(Nb)';% Keep the same permutation for stresses and temperatures
                Prob_SU_Strs{Tube,C} = Prob_SU_Strs{Tube,C}(SU_RandPerm,:);
                Prob_SU_Temps{Tube,C} = Prob_SU_Temps{Tube,C}(SU_RandPerm);
                
                RT_RandPerm = SU_RandPerm ; % For RTs use the same perm
                Prob_RT_Strs{Tube,C} = Prob_RT_Strs{Tube,C}(RT_RandPerm,:);
                Prob_RT_Temps{Tube,C} = Prob_RT_Temps{Tube,C}(RT_RandPerm);
                 
            case 'Deterministic'
                
                % Assigning the deterministic transient stresses according
                % to the ASSUMED most dominant stress component
                
                DomStrComp = 2;
                
                [~,SU_DomStrComp_Order] = sort(Prob_SU_Strs{Tube,C}(:,DomStrComp));
                [~,RT_DomStrComp_Order] = sort(Prob_RT_Strs{Tube,C}(:,DomStrComp));
                
                Prob_SU_Strs{Tube,C} = Prob_SU_Strs{Tube,C}(SU_DomStrComp_Order,:);
                Prob_RT_Strs{Tube,C} = Prob_RT_Strs{Tube,C}(RT_DomStrComp_Order,:);
                
                Prob_SU_Strs{Tube,C} = Prob_SU_Strs{Tube,C}(LHS(:,10),:);
                Prob_RT_Strs{Tube,C} = Prob_RT_Strs{Tube,C}(LHS(:,11),:);
                
                % Assigning the deterministic transient temperatures
                
                Sorted_Prob_SU_Temps = sort(Prob_SU_Temps{Tube,C});
                Sorted_Prob_RT_Temps = sort(Prob_RT_Temps{Tube,C});
                
                Prob_SU_Temps{Tube,C} = Sorted_Prob_SU_Temps(LHS(:,12));
                Prob_RT_Temps{Tube,C} = Sorted_Prob_RT_Temps(LHS(:,13));
        end
    end
end

% Plot histograms for all transient SCs and metal temperatures, and finding
% the most onerous transient stress states
switch AnalysisType
    case 'Probabilistic'
        if Plot_Transient_Histograms
            PlotTransientHistograms(Prob_SU_Strs,Prob_SU_Temps,Prob_RT_Strs,Prob_RT_Temps)
        end
end

end

function PlotSS_TempHistograms(Diff_Steam_vs_Metal_Temps)

Direct = cd;

figure;whitebg('w'); set(gcf,'color','w');

H1 = histogram(Diff_Steam_vs_Metal_Temps,80,'Normalization','pdf');hold on;
H1.FaceColor = [180 180 180]./255;


dT_Dist = UoB_DistFitter_MLE(Diff_Steam_vs_Metal_Temps,'Normal');




x = -40:.01:40;
dT_pdf = pdf(dT_Dist.pd,x);

plot(x,dT_pdf,'-k','Linewidth',3); 


xlabel(['Temperature difference/[�C]']),ylabel('Probability density function (PDF)');
set(gca,'FontSize',14,'fontWeight','bold');
set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
set(gca,'LineWidth',2);


B = gcf;
B.CurrentAxes.YLim = [0 max(H1.Values*1.05)];
B.CurrentAxes.XLim = [-60 60];

set(gcf,'pos',[250 100 400 500])

cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Plots for Journal Paper\Differences_between_steam_and_metal_temperatures'], '-jpg');
export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Plots for Journal Paper\Differences_between_steam_and_metal_temperatures'], '-pdf');
cd(Direct)


end

function PlotTransientHistograms(Prob_SU_Strs,Prob_SU_Temps,Prob_RT_Strs,Prob_RT_Temps)

Direct = cd;

Tube = 2;
C = 1; % All cycles should have the same histogram

SP_Discrip = {'S11', 'S22', 'S33', 'S12' 'S13' 'S23'};

No_Bins = 20;

for SC_No = 2 %1:6
    
    
    figure;whitebg('w'); set(gcf,'color','w');
    
    SU_SC = Prob_SU_Strs{Tube,C}(:,SC_No);
    
    H1 = histogram(SU_SC,No_Bins,'Normalization','probability');
    
    xlabel([SP_Discrip{SC_No} ' stress /[MPa]']),ylabel('Frequency');
    set(gca,'FontSize',14,'fontWeight','bold');
    set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
    set(gca,'LineWidth',2);
    grid on;
    
    H1.FaceColor = [99 99 99]./255;
    B = gcf;
    B.CurrentAxes.YLim = [0 max(H1.Values)*1.1];
    
    set(gcf,'pos',[250 100 400 400])
    
    cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
    %export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Plots for Journal Paper\Transient_SU_Tube_' num2str(Tube) 'SP_' SP_Discrip{SC_No}], '-jpg');
    
    figure;whitebg('w'); set(gcf,'color','w');
    
    RT_SC = Prob_RT_Strs{Tube,C}(:,SC_No);
    
    H1 = histogram(RT_SC,No_Bins,'Normalization','probability');
    
    xlabel([SP_Discrip{SC_No} ' stress /[MPa]']),ylabel('Frequency');
    set(gca,'FontSize',14,'fontWeight','bold');
    set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
    set(gca,'LineWidth',2);
    grid on;
    H1.FaceColor = [99 99 99]./255;
    B = gcf;
    B.CurrentAxes.YLim = [0 max(H1.Values)*1.1];
    
    set(gcf,'pos',[250 100 400 400])
    
    cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
    %export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Plots for Journal Paper\Transient_RT_Tube_' num2str(Tube) 'SP_' SP_Discrip{SC_No}], '-jpg');
    
    
end

figure;whitebg('w'); set(gcf,'color','w');

SU_Temp = Prob_SU_Temps{Tube,C};

H1 = histogram(SU_Temp,No_Bins,'Normalization','probability');

xlabel('Minimum metal temperature/[�C]'),ylabel('Frequency');
set(gca,'FontSize',14,'fontWeight','bold');
set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
set(gca,'LineWidth',2);

H1.FaceColor = [99 99 99]./255;
B = gcf;
B.CurrentAxes.YLim = [0 max(H1.Values+0.1)];

set(gcf,'pos',[250 100 400 400])


cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
% export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Plots for Journal Paper\Transient_SU_Tube_' num2str(Tube) '_MinTemps'], '-jpg');


figure;whitebg('w'); set(gcf,'color','w');

RT_Temp = Prob_RT_Temps{Tube,C};

H1 = histogram(RT_Temp,No_Bins,'Normalization','probability');

xlabel('Maximum metal temperature/[�C]'),ylabel('Frequency');
set(gca,'FontSize',14,'fontWeight','bold');
set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
set(gca,'LineWidth',2);

H1.FaceColor = [99 99 99]./255;
B = gcf;
B.CurrentAxes.YLim = [0 max(H1.Values+0.1)];

set(gcf,'pos',[250 100 400 400])

cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
% export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Plots for Journal Paper\Transient_RT_Tube_' num2str(Tube) '_MaxTemps'], '-jpg');



cd(Direct)

close all;




%% Finding the most severe transients
Max_SU_SC = 2;
[~,I_Max] = max(abs(Prob_SU_Strs{Tube,C}(:,Max_SU_SC)));

Most_Onerous_SU = Prob_SU_Strs{Tube,C}(I_Max,:);
Temp_for_Most_Onerous_SU  = Prob_SU_Temps{Tube,C}(I_Max,:);



Max_RT_SC = 3;
[~,I_min] = min(abs(Prob_RT_Strs{Tube,C}(:,Max_RT_SC)));
Most_Onerous_RT = Prob_RT_Strs{Tube,C}(I_min,:);
Temp_for_Most_Onerous_RT  = Prob_RT_Temps{Tube,C}(I_min,:);

[~,I_Max] = min(max(Prob_RT_Strs{Tube,C},[],2));
Most_Onerous_RT = Prob_RT_Strs{Tube,C}(I_Max,:);
Temp_for_Most_Onerous_RT  = Prob_RT_Temps{Tube,C}(I_Max,:);


%% Plotting histograms for Stress vs Metal temprature correlations

% Only looking at the correlations with the largest stress components for
% SU which is Sigma_22 and for RT which is Sigma_33


for Tube = 1:37
    SU_Dominant_SC = Prob_SU_Strs{Tube,C}(:,2);
    RT_Dominant_SC = Prob_RT_Strs{Tube,C}(:,2);
    
    SU_Temp = Prob_SU_Temps{Tube,C};
    RT_Temp = Prob_RT_Temps{Tube,C};
    
    
    SU_Corr(Tube) = corr(SU_Temp,SU_Dominant_SC,'Type','spearman');
    RT_Corr(Tube) = corr(RT_Temp,RT_Dominant_SC,'Type','spearman');
    
end

figure; whitebg('w'); set(gcf,'color','w');
Hist_Temp_Stress_Corr = histogram(SU_Corr, 'Normalization',  'probability');

xlabel('Spearman correlation'),ylabel('Frequency');
set(gca,'FontSize',14,'fontWeight','bold');
set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
set(gca,'LineWidth',2);

Hist_Temp_Stress_Corr.FaceColor = [99 99 99]./255;
B = gcf;
B.CurrentAxes.YLim = [0 max(Hist_Temp_Stress_Corr.Values)*1.2];
% B.CurrentAxes.XLim = [-1 1];

set(gcf,'pos',[250 100 400 400])

cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
% export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Plots for Journal Paper\SU_Temp_Stress_Corr_Most_Dom_StrComp'], '-jpg');


figure; whitebg('w'); set(gcf,'color','w');
Hist_Temp_Stress_Corr = histogram(RT_Corr, 'Normalization',  'probability');

xlabel('Spearman correlation'),ylabel('Frequency');
set(gca,'FontSize',14,'fontWeight','bold');
set(findall(gcf,'type','text'),'fontSize',14,'fontWeight','bold');
set(gca,'LineWidth',2);

Hist_Temp_Stress_Corr.FaceColor = [99 99 99]./255;
B = gcf;
B.CurrentAxes.YLim = [0 max(Hist_Temp_Stress_Corr.Values)*1.2];
B.CurrentAxes.XLim = [-1 0];

set(gcf,'pos',[250 100 400 400])

cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
% export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Plots for Journal Paper\RT_Temp_Stress_Corr_Most_Dom_StrComp'], '-jpg');



end


%% Scripts for steady-operation stresses

function Validate_Samples_against_FE(Str_Comps_Samples,No_Asmt_Locations_Per_Tube,Tubes,Nb,CycleNo)


Stress_Components = {'S11' 'S22' 'S33' 'S12' 'S13' 'S23'};

Validation_Tilts = 10:1:194;

for Tube = Tubes
    for A = 1:No_Asmt_Locations_Per_Tube
        figure(Tube); whitebg('w'); set(gcf,'color','w');
        
        for No_Tilt = 1:length(Validation_Tilts)
            
            Tilt = Validation_Tilts(No_Tilt);
            All_Ys = [];
            
            for SC = 1:6
                All_Ys = horzcat(All_Ys, Str_Comps_Samples{Tube}{No_Tilt}(:,SC));
            end
            
            Plot_Ranges = 0;
            Predicted_Stress_Ranges{Tube}{No_Tilt} = Calcualte_Stress_Ranges(ones(length(All_Ys),1).*Tilt,All_Ys,Tube,A,Plot_Ranges,Nb,CycleNo);
            
            gcf; plot(ones(length(Predicted_Stress_Ranges{Tube}{No_Tilt}),1).*Tilt,...
                Predicted_Stress_Ranges{Tube}{No_Tilt},...
                'o','MarkerFaceColor',[204 204 204]./255, 'MarkerEdgeColor',[204 204 204]./255); hold on;
        end
        
        
        xlabel('Tilt/[�C]'); ylabel('Stress Range/[MPa]');
        set(gca,'FontSize',16,'fontWeight','bold');
        set(findall(gcf,'type','text'),'fontSize',16,'fontWeight','bold');
        set(gca,'LineWidth',2);
        gcf; title(['Tube: ' num2str(Tube) ' // Asmt Loc: ' num2str(A)])
        set(gcf,'pos',[250 100 1500 600])
        grid on;
        
        Direct = cd;
        cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
        export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Stress Analysis Plots\Prob_Stress_Validation_' num2str(Tube) '_Asmt_Loc_' num2str(A)], '-jpg');
        cd(Direct)
        
        
        close(gcf)
        
    end
end

end

%% Scripts for stress ranges calculations and solving the Ramberg-Osgood expression

function [VM_Stress_Range,StressRange_Sign] = VM_Str_Range_V2(Stress_State_1,Stress_State_2)

Stress_Ranges = Stress_State_2 - Stress_State_1;

if size(Stress_Ranges,2) == 3 % This means only PSCs
    
    VM_Stress_Range = (0.5.*((Stress_Ranges(:,1) - Stress_Ranges(:,2)).^2 + ...
        (Stress_Ranges(:,2) - Stress_Ranges(:,3)).^2 + ...
        (Stress_Ranges(:,3) - Stress_Ranges(:,1)).^2)).^0.5;
    
else
    
    VM_Stress_Range = (0.5.*((Stress_Ranges(:,1) - Stress_Ranges(:,2)).^2 + ...
        (Stress_Ranges(:,2) - Stress_Ranges(:,3)).^2 + ...
        (Stress_Ranges(:,3) - Stress_Ranges(:,1)).^2 + ...
        6.*(Stress_Ranges(:,4).^2 + Stress_Ranges(:,5).^2 + Stress_Ranges(:,6).^2))).^0.5;
    
    
end

[~, I_Max] = max(abs(Stress_Ranges),[],2);

StressRange_Sign = sign(Stress_Ranges(I_Max));

end

function [StressRanges,Tilts] = Calcualte_Stress_Ranges(X,All_Ys,Tube,A,Plot_Ranges,Nb,CycleNo)
%% Loading the SU transient data, and calculating the stress ranges

Direct = cd;

[Prob_SU_Strs,~,~,~] = AssignCycleTransients(Nb,LHS,CycleNo,Tube,0,AnalysisType);

cd(Direct)

[~,Unique_SU_Indx,~] = unique(Prob_SU_Strs{Tube,1}(:,1));

SU_Strs = Prob_SU_Strs{Tube,1}(Unique_SU_Indx,:);


% Calculating the stress ranges for each event based on the all SU
% transients

Event_Stress_Range = [];
Tilts = [];

for i = 1:length(SU_Strs)
    Event_Stress_Range = vertcat(Event_Stress_Range,VM_Str_Range_V2(ones(length(All_Ys),1)*SU_Strs(i,:),All_Ys));
    Tilts = vertcat(Tilts,X);
end


StressRanges = Event_Stress_Range;

if Plot_Ranges
    
    figure; whitebg('w'); set(gcf,'color','w');
    plot(Tilts,StressRanges,'o','MarkerFaceColor',[204 204 204]./255, 'MarkerEdgeColor','k');
    xlabel('Tilt/[�C]'); ylabel('Stress Range/[MPa]');
    set(gca,'FontSize',16,'fontWeight','bold');
    set(findall(gcf,'type','text'),'fontSize',16,'fontWeight','bold');
    set(gca,'LineWidth',2);
    gcf; title(['Tube: ' num2str(Tube) ' // Asmt Loc: ' num2str(A)])
    set(gcf,'pos',[250 100 1500 600])
    grid on;
    
    
    % cd('C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\Export_Fig_Files')
    % export_fig(['C:\Users\nz9512\Google Drive\1. PhD Work\3. TPL FEA\PlayGround\9. Stress Probabilistic Modelling\Stress Analysis Plots\Stress_Ranges_Tube_' num2str(Tube) '_Asmt Loc_' num2str(A)], '-jpg');
    
end


end

function S_new = Solve_RambergOsgood(Sigma_el,SigmaRupRef,Sigma_RD,A,Beta,E_bar,Nb,AnalysisType)


% Initial guess to see which stress ranges give imaginary stresses

switch AnalysisType
    case 'Deterministic'
        Sigma_RD  = ones(Nb,1).*Sigma_RD;
        E_bar = ones(Nb,1).*E_bar;
        A = ones(Nb,1).*A;
        Beta = ones(Nb,1).*Beta;
end


S_old = ones(Nb,1).* 500; % The initaial guess in Newton-Raphson
S_new = zeros(Nb,1);
err = ones(Nb,1).*100;
Eqn = zeros(Nb,1);
dEqn = zeros(Nb,1);

if length(Sigma_el) == 1
    Sigma_el = ones(Nb,1).*Sigma_el;
end


Mask = (imag(S_old) == 0); % This is to differenciate between the elastic stress ranges that give imaginary Sigma_Bs.

while max(err(Mask)) > 1/100
    
    Eqn(Mask) = ((Sigma_RD(Mask) + S_old(Mask))./(E_bar(Mask)) + ...
        (2.*S_old(Mask)./A(Mask)).^(1./Beta(Mask))).*(Sigma_RD(Mask) + S_old(Mask)) - Sigma_el(Mask).^2./E_bar(Mask);
    
    dEqn(Mask) = (S_old(Mask) + Sigma_RD(Mask))./E_bar(Mask) + ((2.*S_old(Mask))./A(Mask)).^(1./Beta(Mask)) + ...
        (S_old(Mask) + Sigma_RD(Mask)).*(1./E_bar(Mask) + ...
        (2.*((2.*S_old(Mask))./A(Mask)).^(1./Beta(Mask) - 1))./(A(Mask).*Beta(Mask)));
    
    S_new(Mask) = S_old(Mask) - Eqn(Mask)./dEqn(Mask);
    err(Mask) = abs(S_new(Mask) - S_old(Mask));
    S_old(Mask) = S_new(Mask);
    
    Mask = (imag(S_old) == 0); % Update to see which ranges gave imaginary solutions
    
    % This is to account for the fact that given any comination of all
    % parameters except Sigma_el, there is a minimum Sigma_el below which
    % the Ramberg-Osgood expression gives imaginary solutions:
    
    S_new(~Mask) = SigmaRupRef; % The options for this are either zero or SigmaRupRef. The latter is more conservative!
    
end


S_new(S_new < SigmaRupRef) = SigmaRupRef;

% Just a check to see if the stresses have gone imaginary:
if sum(imag(S_new)~=0) > 0
    p
end

end

%% Scripts for calculating creep parameters

function [UniDuct_S_Frac,Sigma_H,Sigma_1,Sigma_VM,Flag_NoCreepDamage] = SpindlerFraction(Event_Stress_Comps)

p = 0.15;
q = 1.25;

PSCs = zeros(size(Event_Stress_Comps,1),3);

for S = 1:size(Event_Stress_Comps,1)
    StressTensor = [ Event_Stress_Comps(S,1) Event_Stress_Comps(S,4) Event_Stress_Comps(S,5);...
        Event_Stress_Comps(S,4) Event_Stress_Comps(S,2) Event_Stress_Comps(S,6);...
        Event_Stress_Comps(S,5) Event_Stress_Comps(S,6) Event_Stress_Comps(S,3)];
    
    PSCs(S,:) = eig(StressTensor)';
    
end

Sigma_VM = (0.5.*((Event_Stress_Comps(:,1) - Event_Stress_Comps(:,2)).^2 + ...
    (Event_Stress_Comps(:,2) - Event_Stress_Comps(:,3)).^2 + ...
    (Event_Stress_Comps(:,3) - Event_Stress_Comps(:,1)).^2 + ...
    6*(Event_Stress_Comps(:,4).^2 + Event_Stress_Comps(:,5).^2 + Event_Stress_Comps(:,6).^2))).^0.5;

Sigma_H = (PSCs(:,1) + PSCs(:,2) + PSCs(:,3))./3;

Sigma_1 = max(PSCs,[],2); % Maximum Principal Stress by size rather then sign

% % Only calculate the Spindler Fraction when:
%  1. The maximum principal stress is positive
%  2. The hydrostatic stress is positive
%  3. The signed Von Mises stress stress is positive (same as the point 1 really)

% This is what 'Mask' does.

UniDuct_S_Frac = zeros(size(Event_Stress_Comps,1),1);

Mask = logical((Sigma_H > 0).*(Sigma_1 > 0));


UniDuct_S_Frac(Mask) = exp(p.*(1-Sigma_1(Mask)./Sigma_VM(Mask))).*exp(q.*(0.5-((3.*Sigma_H(Mask))./(2.*Sigma_VM(Mask)))));
UniDuct_S_Frac(~Mask) = 1;
UniDuct_S_Frac(UniDuct_S_Frac>1) = 1;
Flag_NoCreepDamage = ~Mask;



end

function [ProbTransStrs,ProbTransTemps,Det_Strs,Det_Temps] = ProbTransStrComps(Trans_SS_Stress_Comp_Order,Nb,Tube,TransientType,LocationOption,TempOption)

switch TransientType
    
    case 'SU'
        
        load('SU_Transient_Analysis_Results.mat')
        
        % Use the same permutations for stresses and temp to avoid worrying about correlations
        SU_Permuations = [];
        
        for S = 1:(Nb/20)
            SU_Permuations = vertcat(SU_Permuations,randperm(20)');
        end
        
        SU_Permuations = SU_Permuations(randperm(Nb));
        
        
        Det_SU_Strs = [];
        Det_SU_Temps = [];
        
        switch  LocationOption
            case 'MaxStressLocation'
                for No_SU = 1:20
                    SU_SCs = Transient_Analysis_Results{No_SU,Tube}.Assessment_Transient_Stress_Components;
                    Det_SU_Strs = vertcat(Det_SU_Strs,SU_SCs);
                end
        end
        
        switch TempOption
            case 'MaxTemp'
                for No_SU = 1:20
                    SU_Temps = Transient_Analysis_Results{No_SU,Tube}.Max_Temp;
                    Det_SU_Temps = vertcat(Det_SU_Temps,SU_Temps);
                end
                
            case 'MinTemp'
                for No_SU = 1:20
                    SU_Temps = Transient_Analysis_Results{No_SU,Tube}.Min_Temp;
                    Det_SU_Temps = vertcat(Det_SU_Temps,SU_Temps);
                end
        end
        
        SU_Strs = Det_SU_Strs(SU_Permuations,Trans_SS_Stress_Comp_Order);
        SU_Temps = Det_SU_Temps(SU_Permuations,:);
        
        ProbTransStrs = SU_Strs;
        ProbTransTemps = SU_Temps;
        
        Det_Strs = Det_SU_Strs;
        Det_Temps = Det_SU_Temps;
        
        
    case 'RT'
        
        load('Transient_Analysis_Results_RT.mat')
        
        Det_RT_Strs = [];
        Det_RT_Temps = [];
        
        switch LocationOption
            case 'MaxStressLocation'
                for No_RT = 1:18
                    RT_SCs = Transient_Analysis_Results{No_RT,Tube}.Assessment_Transient_Stress_Components.MaxStressLocation;
                    Det_RT_Strs = vertcat(Det_RT_Strs,RT_SCs);
                    
                    switch TempOption
                        case 'MaxTemp'
                            RT_Temps = Transient_Analysis_Results{No_RT,Tube}.Max_Temp;
                            Det_RT_Temps = vertcat(Det_RT_Temps,RT_Temps);
                            
                        case 'MinTemp'
                            RT_Temps = Transient_Analysis_Results{No_RT,Tube}.Min_Temp;
                            Det_RT_Temps = vertcat(Det_RT_Temps,RT_Temps);
                    end
                end
                
            case 'MaxRangeLocation'
                for No_RT = 1:18
                    RT_SCs = Transient_Analysis_Results{No_RT,Tube}.Assessment_Transient_Stress_Components.MaxRangeLocation;
                    [~,IR,~] = unique(RT_SCs(:,1));
                    RT_SCs = RT_SCs(IR,:);
                    Det_RT_Strs = vertcat(Det_RT_Strs,RT_SCs);
                    switch TempOption
                        case 'MaxTemp'
                            RT_Temps = max(Transient_Analysis_Results{No_RT,Tube}.Max_Temp);
                            Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(IR),1)*RT_Temps);
                            
                        case 'MinTemp'
                            RT_Temps = min(Transient_Analysis_Results{No_RT,Tube}.Min_Temp);
                            Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(IR),1)*RT_Temps);
                    end
                end
                
            case 'MinRangeLocation'
                for No_RT = 1:18
                    RT_SCs = Transient_Analysis_Results{No_RT,Tube}.Assessment_Transient_Stress_Components.MinRangeLocation;
                    % [~,IR,~] = unique(RT_SCs(:,1));
                    % RT_SCs = RT_SCs(IR,:);
                    Det_RT_Strs = vertcat(Det_RT_Strs,RT_SCs);
                    switch TempOption
                        case 'MaxTemp'
                            RT_Temps = max(Transient_Analysis_Results{No_RT,Tube}.Max_Temp);
                            % Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(IR),1)*RT_Temps);
                            Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(RT_SCs),1)*RT_Temps);
                            
                        case 'MinTemp'
                            RT_Temps = min(Transient_Analysis_Results{No_RT,Tube}.Min_Temp);
                            % Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(IR),1)*RT_Temps);
                            Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(RT_SCs),1)*RT_Temps);
                    end
                end
                
                
            case 'SU_Location'
                for No_RT = 1:18
                    RT_SCs = Transient_Analysis_Results{No_RT,Tube}.Assessment_Transient_Stress_Components.SU_Location;
                    % [~,IR,~] = unique(RT_SCs(:,1));
                    % RT_SCs = RT_SCs(IR,:);
                    Det_RT_Strs = vertcat(Det_RT_Strs,RT_SCs);
                    switch TempOption
                        case 'MaxTemp'
                            RT_Temps = max(Transient_Analysis_Results{No_RT,Tube}.Max_Temp);
                            % Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(IR),1)*RT_Temps);
                            Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(RT_SCs),1)*RT_Temps);
                            
                        case 'MinTemp'
                            RT_Temps = min(Transient_Analysis_Results{No_RT,Tube}.Min_Temp);
                            % Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(IR),1)*RT_Temps);
                            Det_RT_Temps = vertcat(Det_RT_Temps,ones(length(RT_SCs),1)*RT_Temps);
                    end
                end
                
                
        end
        
        % Use the same permutations for stresses and temp to avoid worrying about correlations
        RT_Permuations = [];
        
        for R = 1:ceil((Nb/length(Det_RT_Strs)))
            RT_Permuations = vertcat(RT_Permuations,randperm(length(Det_RT_Strs))');
        end
        
        RT_Permuations = RT_Permuations(randperm(Nb));
        
        RT_Strs = Det_RT_Strs(RT_Permuations,Trans_SS_Stress_Comp_Order);
        RT_Temps = Det_RT_Temps(RT_Permuations,:);
        
        ProbTransStrs = RT_Strs;
        ProbTransTemps = RT_Temps;
        
        Det_Strs = Det_RT_Strs;
        Det_Temps = Det_RT_Temps;
        
end

end

function Temp_Index = FindExtrapIndex(T_Hot,Extrap_Temps)

% This find the indeies of Extrap_Temps corrisponding to the elements in T_Hot

T_Hot_R = round(T_Hot,4, 'significant');
Extrap_Temps_R = round(Extrap_Temps',4, 'significant');

[~,~,IU] = unique(T_Hot_R);

[Ix] = find(ismember(Extrap_Temps_R,T_Hot_R,'rows'));

Temp_Index = Ix(IU);


end


function [Creep_Strain_Rate,Creep_Strain_Rate_Ref] = Prob_Creep_Rate(Creep_Strain,Plastic_Strain,Zeta_P,Accumlated_creep_strain,Dwell_Stress,SigmaRupRef,Event_Temp,Normalised_Bins,LHS,PR_Options)

[Creep_Strain_Rate,Creep_Strain_Rate_LB,Creep_Strain_Rate_Ref] = HTBASS(Creep_Strain,Plastic_Strain,Zeta_P,Accumlated_creep_strain,Dwell_Stress,SigmaRupRef,Event_Temp,PR_Options);

ConfLimit = 0.95;
ConfFactors = norminv([(1-ConfLimit)/2 1-(1-ConfLimit)/2]);
ConfFactor = (ConfFactors(2)-ConfFactors(1))/2;

% Assuming a Log-Normal Distribution for ductility
STD = log10(Creep_Strain_Rate./Creep_Strain_Rate_LB)./ConfFactor;
Mu = log10(Creep_Strain_Rate);

Creep_Strain_Rate =   10.^(Normalised_Bins(LHS).*STD + Mu);

end

function Varep_f = Prob_Varep_f(Dwell_Stress,SigmaFrac_1_VM,SigmaFrac_H_VM,Creep_Strain_Rate,Event_Temp,Normalised_Bins,LHS,UniDuct_S_Frac,Flag_NoCreepDamage,ConfLimit,ConfFactor,AnalysisType)

Ductility_Approach = 'Const. DE';

Capping_Assumption = 'Min DE';

% Approximating the maximum principal stress
Sigma_1 = Dwell_Stress.*SigmaFrac_1_VM;

Varep_f_Mean = zeros(size(Sigma_1));
Varep_f_SMDE_LB = zeros(size(Sigma_1));

Varep_f = zeros(size(Sigma_1));


switch Ductility_Approach
    
    case 'SMDE'
        
        % STEP1 : Calculating the ductility (mean and LB) besed on SMDE model:
        % Note: only non-compressive trials are considered
        [Varep_f_Mean(~Flag_NoCreepDamage),Varep_f_SMDE_LB(~Flag_NoCreepDamage)] = ...
            SMDE(Sigma_1(~Flag_NoCreepDamage),SigmaFrac_1_VM(~Flag_NoCreepDamage),SigmaFrac_H_VM(~Flag_NoCreepDamage),Creep_Strain_Rate(~Flag_NoCreepDamage),Event_Temp(~Flag_NoCreepDamage));
        
        % STEP 2: Assuming a Normal Distribution for ductility in the case
        % of SMDE. This is based on the assumption that the LB is at the
        % 95% lower confidence limit of the distribution. This assumption
        % is needed to calcualte the standard deviation.
        
        Assumed_Distribution = 'Log-Normal';
        
        
        Dist_Type = '3-P Lognormal'; % or '3-P Weibull': Dist_Type = '3-P Weibull';
        
        Minimum_Recorded_Value = 1.7/100; % this is in absolute mm/mm.
        Varep_f_min = Minimum_Recorded_Value;
        
        Varep_f_Normal_Bins = Normalised_Bins(LHS);
        
        Varep_f(~Flag_NoCreepDamage) = SMDE_Samples(Varep_f_Mean(~Flag_NoCreepDamage),...
            Varep_f_SMDE_LB(~Flag_NoCreepDamage),...
            Varep_f_min,...
            Dist_Type,...
            ConfLimit,...
            Varep_f_Normal_Bins(~Flag_NoCreepDamage),...
            Normalised_Bins);
        
        
    case 'Const. DE'
        
        
        
        Dist_Type = '3-P Lognormal'; % or '3-P Weibull': Dist_Type = '3-P Weibull'
        
        % Assuming a 2-P Log-Normal Distribution for ductility
        STD_log_Varep_f = 0.299;
        Mu_log_Varep_f = 1.029;
        
        Minimum_Recorded_Value = 1.7/100; % this is in absolute mm/mm.
        Varep_f_min = Minimum_Recorded_Value;

         
        Varep_f_Mean = 10^(Mu_log_Varep_f)/100;
        Varep_f_LB = (10^(Mu_log_Varep_f - ConfFactor.*STD_log_Varep_f))./100;
        
        Varep_f_All_Samples = Ductility_Samples(Varep_f_Mean,Varep_f_LB,Varep_f_min,Dist_Type,ConfLimit,Normalised_Bins);
        
        switch AnalysisType
            case 'Probabilistic'
                Varep_f = Varep_f_All_Samples(LHS);
                Varep_f(Flag_NoCreepDamage) = inf; % Set the ductility for compressive trials to a huge number
                
            case 'Deterministic'
                Varep_f = Varep_f_All_Samples(LHS);
        end
        
        
        Varep_f = Varep_f.*UniDuct_S_Frac; % accounting for triaxiality
        
        %        figure; histogram(Varep_f(~Flag_NoCreepDamage)); hold on; histogram(Varep_f_No_Min(~Flag_NoCreepDamage))
        
        
    case 'Creep Rate Dep. DE'
        
        % THIS OPTION IS WORK IN PROGRESS
        
        Varep_U = 0.3923;
        Varep_L = 0.0257;
        B = 0.5967;
        n = 0.2826;
        
        Mu_Varep_f = min(Varep_U,max(Varep_L,B.*Creep_Strain_Rate.^n));
        
        Varep_f = Mu_Varep_f;
        
end



end


function Fatigue = FatigueDamage_V2(Varep_T,Temp,ConfFactor,Normalised_Bins,LHS)

Nf_BE = CalculateFatigueEndurance(1.00.*Varep_T,Temp);
Nf_LB = CalculateFatigueEndurance(0.75.*Varep_T,Temp);

% if sum(Nf_BE>10^5)
%     disp('ERROR: Fatigue validity range exceeded!!!')
% end

Mu = log10(Nf_BE);
STD = (log10(Nf_LB) - log10(Nf_BE))./ConfFactor;

Nf_Samples = 10.^(Normalised_Bins(LHS).*STD + Mu);

a_o = 0.2;
a_min = 0.2;
a_i = 0.02;
a_l = 10;
M = (a_min.*log(a_o./a_min)+(a_min-a_i))./(a_min*log(a_l./a_min)+(a_min-a_i));

Ni = Nf_Samples.*exp(-8.06.*Nf_Samples.^(-0.28));
Ng = Nf_Samples - Ni;
Ng_dash = Ng.*M;

N0 = Ng_dash + Ni;

Fatigue =  1./N0;


end

function Nf = CalculateFatigueEndurance(Varep_T,Temp)

A =  1.2107;
B =  0.8471;
C =  0.50063;
D =  0.18694;
E =  0.028217;
F =  0.30373;
G =  -0.079609;
H =  0.014056;
J =  -0.00079288;
K =  0.29465;
L =  0.21935;
M =  0.068013;
P =  0.0069224;

S = log10(Varep_T);
T  = Temp./100;

N = A + B.*S + C.*S.^2 + D.*S.^3 + E.*S.^4 + ...
    F.*T + G.*T.^2 + H.*T.^3 + J.*T.^4 + ...
    K.*T.*S + L.*T.*S.^2 + M.*T.*S.^3 + P.*T.*S.^4;

Nf = 10.^(N.^-2);

end

function [VM_Stress_Range,StressRange_Sign] = VM_Str_Range(Stress_State_1,Stress_State_2)


Stress_Ranges = Stress_State_2 - Stress_State_1;


VM_Stress_Range = (0.5.*((Stress_Ranges(:,1) - Stress_Ranges(:,2)).^2 + ...
    (Stress_Ranges(:,2) - Stress_Ranges(:,3)).^2 + ...
    (Stress_Ranges(:,3) - Stress_Ranges(:,1)).^2 + ...
    6*(Stress_Ranges(:,4).^2 + Stress_Ranges(:,5).^2 + Stress_Ranges(:,6).^2))).^0.5;



[~, I_Max] = max(abs(Stress_Ranges),[],2);




for i = 1:length(I_Max)
    StressRange_Sign(i,1) = sign(Stress_Ranges(i,I_Max(i)));
end

end

function [VM_Stress_Range] = Simple_VM_Str_Range(Stress_State_1,Stress_State_2)

if size(Stress_State_2,1) ~= size(Stress_State_1,1)
    Stress_State_1 = ones(size(Stress_State_2,1),1)*Stress_State_1;
end

Stress_Ranges = Stress_State_2 - Stress_State_1;

VM_Stress_Range = (0.5.*((Stress_Ranges(:,1) - Stress_Ranges(:,2)).^2 + ...
    (Stress_Ranges(:,2) - Stress_Ranges(:,3)).^2 + ...
    (Stress_Ranges(:,3) - Stress_Ranges(:,1)).^2 + ...
    6*(Stress_Ranges(:,4).^2 + Stress_Ranges(:,5).^2 + Stress_Ranges(:,6).^2))).^0.5;

end


function [Creep_Strain_Rate,Creep_Strain_Rate_LB,Creep_Strain_Rate_Ref] = HTBASS(creep_strain,plastic_strain,Zeta_P,Accumlated_creep_strain,Sigma,SigmaRef,Temp,PR_Options)

Qp = 474024;
R = 8.3144598;
T = 273+Temp; % Converting to kelvin
D = 9.19634e-4;
x_0 = -7.23794;
x_1 = 5.08362e-3;
Beta = 0.261108;
C_0 = 10^(24.7512);
Q_s = 773904;
T_n = 4194.56;
Gamma = -1.28005;

RMSLE = 0.3805;


switch PR_Options
    case 'Zeta_P'
        
        Primary_Rate_CH =  (exp(-Qp./(R.*T)).*(Accumlated_creep_strain + D.*plastic_strain).^(x_0+x_1*T).*Sigma.^(T.^Beta));
        Primary_Rate_PR =  (exp(-Qp./(R.*T)).*(creep_strain            + D.*plastic_strain).^(x_0+x_1*T).*Sigma.^(T.^Beta));
        Seconday_Rate = (C_0.*exp(-Q_s./(R.*T)).*Sigma.^((T./T_n).^Gamma));
        
        Creep_Strain_Rate = Primary_Rate_CH + Zeta_P.*Primary_Rate_PR + Seconday_Rate;
        
    otherwise
        
        Primary_Rate =  (exp(-Qp./(R.*T)).*(creep_strain            + D.*plastic_strain).^(x_0+x_1*T).*Sigma.^(T.^Beta));
        Seconday_Rate = (C_0.*exp(-Q_s./(R.*T)).*Sigma.^((T./T_n).^Gamma));
        
        Creep_Strain_Rate = Primary_Rate + Seconday_Rate;
        
end



while sum(max(abs(imag(Creep_Strain_Rate)))) > 0  % This means that the HTBASS model has failed becaue the creep strain is too small
    
    creep_strain(imag(Creep_Strain_Rate)~=0) = creep_strain(imag(Creep_Strain_Rate)~=0).*1.01;
    
    switch PR_Options
        case 'Zeta_P'
            Primary_Rate_CH =  (exp(-Qp./(R.*T)).*(Accumlated_creep_strain + D.*plastic_strain).^(x_0+x_1*T).*Sigma.^(T.^Beta));
            Primary_Rate_PR =  (exp(-Qp./(R.*T)).*(creep_strain            + D.*plastic_strain).^(x_0+x_1*T).*Sigma.^(T.^Beta));
            Seconday_Rate = (C_0.*exp(-Q_s./(R.*T)).*Sigma.^((T./T_n).^Gamma));
            
            Creep_Strain_Rate = Primary_Rate_CH + Zeta_P.*Primary_Rate_PR + Seconday_Rate;
            
        otherwise
            
            Primary_Rate =  (exp(-Qp./(R.*T)).*(creep_strain            + D.*plastic_strain).^(x_0+x_1*T).*Sigma.^(T.^Beta));
            Seconday_Rate = (C_0.*exp(-Q_s./(R.*T)).*Sigma.^((T./T_n).^Gamma));
            
            Creep_Strain_Rate = Primary_Rate + Seconday_Rate;
    end
    
    disp('Imaginary creep strain rate!!!')
    
end

switch PR_Options
    case 'Zeta_P'
        Primary_Rate_CH_Ref =  (exp(-Qp./(R.*T)).*(Accumlated_creep_strain + D.*plastic_strain).^(x_0+x_1*T).*SigmaRef.^(T.^Beta));
        Primary_Rate_PR_Ref =  (exp(-Qp./(R.*T)).*(creep_strain            + D.*plastic_strain).^(x_0+x_1*T).*SigmaRef.^(T.^Beta));
        Seconday_Rate_Ref = (C_0.*exp(-Q_s./(R.*T)).*SigmaRef.^((T./T_n).^Gamma));
        
        Creep_Strain_Rate_Ref = Primary_Rate_CH_Ref + Zeta_P.*Primary_Rate_PR_Ref + Seconday_Rate_Ref;
        
    otherwise
        
        Primary_Rate_Ref =  (exp(-Qp./(R.*T)).*(creep_strain            + D.*plastic_strain).^(x_0+x_1*T).*SigmaRef.^(T.^Beta));
        Seconday_Rate_Ref = (C_0.*exp(-Q_s./(R.*T)).*SigmaRef.^((T./T_n).^Gamma));
        
        Creep_Strain_Rate_Ref = Primary_Rate_Ref + Seconday_Rate_Ref;
        
end


% Creep_Strain_Rate_UB = Creep_Strain_Rate.*(10^(2*RMSLE));
Creep_Strain_Rate_LB = Creep_Strain_Rate./(10^(2*RMSLE));


end




function [varep_f_SMDE,varep_f_SMDE_LB] = SMDE(Sigma_1,SigmaFrac_1_VM,SigmaFrac_H_VM,Creep_Strain_Rate,Temp)

% load('RB_Relaxation_Results.mat')
% Temp = 516.1;
%
% Stress = RB_Stress_New;
% Creep_Strain_Rate = RB_CreepStrainRate_New/100;


% Stress Modified Ductility Exhaustion model
A1 = exp(21.3794294);
P1 = 1237.38609;
n1 = 1;
varep_L = exp(-1.49547334);
varep_U = exp(-0.693);
A2 = exp(26.4883122);
P2 = -7146.54039;

m2 = 3.49748603;
m1 = 2.84289979; % With a minus sign????
T = Temp+273;  % Kelvin???

% Stress Modified Ductility Exhaustion model
A1_LB = 1/2.44;
P1_LB = 15975.1087;
n1_LB = 0.931571062;
varep_L_LB = log(1/(1-0.055));
varep_U = exp(-0.693);
A2_LB = exp(10.000);
P2_LB = 0;

m2_LB = 2.494688002;
m1_LB = 2.494688002; % With a minus sign????


%% The SMDE Model

% MultiDuct_SpinlerFraction =  (Sigma_VM./Sigma_1).*exp(0.5 - (3*Sigma_H)./(2*Sigma_VM));

MultiDuct_SpinlerFraction =  (1./SigmaFrac_1_VM).*exp(0.5 - (3/2).*SigmaFrac_H_VM);
%MultiDuct_SpinlerFraction(MultiDuct_SpinlerFraction>1) = 1;

varep_f_SMDE = exp(max(...
    log(A1) + P1./T + n1.*log(Creep_Strain_Rate) + (-m1).*log(Sigma_1),...
    min(log(varep_L).*ones(length(Sigma_1),1),log(A2) + P2./T + (-m2).*log(Sigma_1)))) .* MultiDuct_SpinlerFraction;

varep_f_SMDE_LB = exp(max(...
    log(A1_LB) + P1_LB./T + + n1_LB.*log(Creep_Strain_Rate) + (-m1_LB).*log(Sigma_1),...
    min(log(varep_L_LB).*ones(length(Sigma_1),1),log(A2_LB) + P2_LB./T + (-m2_LB).*log(Sigma_1)))).* MultiDuct_SpinlerFraction;




end


%% Script for assigning metal temperatues according to modes from previus asssessment

function [Temp,Event_Str_Components] = TempStress_Deterministic(Mode)

switch Mode % Taken from Page 64 of M.Stevens report
    case 0 % Mode 1: 525-540�C - >60�C
        Event_Str_Components = [0 0 0 0 0 0 ];
        Temp = 20;
    case 1 % Mode 1: 525-540�C - >60�C
        Event_Str_Components = [32.2 221.7 -13 -75.4 5.4 6.5];
        Temp = 529.0;
    case 2 % Mode 2: 540-550�C - >60�C
        Event_Str_Components = [32.2 221.7 -13 -75.4 5.4 6.5];
        Temp = 539.0;
    case 3 % Mode 3: 550-565�C - >60�C
        Event_Str_Components = [32.2 221.7 -13 -75.4 5.4 6.5];
        Temp = 554.0;
    case 4 % Mode 4: 565-575�C - >60�C
        Event_Str_Components = [66.9 374.3 -10.1 -129.1 9.4 10.4];
        Temp = 554.7;
    case 5 % Mode 0/5: '400-525�C - >60�C'
        Event_Str_Components = [26.1 195 -13.5 -66 4.7 5.8];
        Temp = 514.6;
    case 6 % Normal 1: '525-540�C - <60�C'
        Event_Str_Components = [20 168.2 -14.1 -56.5 4 5.1];
        Temp = 532.0;
    case 7 % Normal 2: 540-550�C - <60�C
        Event_Str_Components = [20 168.2 -14.1 -56.5 4 5.1];
        Temp = 542.0;
    case 8 % Normal 0/3: 400-525�C - <60�C
        Event_Str_Components = [20 168.2 -14.1 -56.5 4 5.1];
        Temp = 516.1;
    case 9
        Event_Str_Components = [0 0 0 0 0 0];
        Temp = 0;
        
end

end


%% Script for loading and sampling the uncertainty in the SO metal temperature

function dT_MetalTemp_Samples = PrepareMetalTempSamples(Nb,Plot_SS_Temp_Histograms)

load('Diff_Steam_vs_Metal_Temps.mat');

if Nb > 1
    dT_MetalTemp_Samples = Histogram_LHS(Diff_Steam_vs_Metal_Temps,Nb);
else
    dT_MetalTemp_Samples = mean(Diff_Steam_vs_Metal_Temps);
end

close all


% Plotting a histogram

if Plot_SS_Temp_Histograms
    PlotSS_TempHistograms(Diff_Steam_vs_Metal_Temps)
end


end


%% Scripts for preparing material properties

function [E_bar_at_Temp,E_at_Temp] = Elastic_Properties_Lookup(Temps)

T =    [20 353.5 358.9 444.4 505.9 525.0 529.0 532.0 539.0 542.0 554.0 554.7];
E_bar = [230579 201456 200984 193518 188148 186480 186130 185868 185257 184995 183947 183886];
E = [198298 173252 172847 166426 161807 160373 160072 159847 159321 159096 158195 158142];

E_bar_F = griddedInterpolant(T,E_bar);
E_bar_at_Temp = E_bar_F(Temps);
E_F = griddedInterpolant(T,E);
E_at_Temp = E_F(Temps);


end

function [A_at_Temp,Beta_at_Temp] = Cyclic_Properties_Lookup(Temps)

% Data from M.Stevens Report
T =    [505.9 514.6 516.1 529.0 532.0 539.0 542.0 554.0 554.7];
Beta = [0.198 0.191 0.189 0.178 0.176 0.170 0.168 0.161 0.161];
A = [2025 1940 1925 1807 1781 1722 1697 1623 1621];

% Data from R66

T_R66 = [450 500 550 600 650 700];
Beta_R66 = [0.363 0.203 0.161 0.166 0.187 0.174];
A_R66 = [4300 2086 1633 1503 1431 1149];


% T = [T, T_R66];
% A = [A, A_R66];
% Beta = [Beta, Beta_R66];

% [T,Inx] = sort(T);
% A = A(Inx);
% Beta = Beta(Inx);


A_F = griddedInterpolant(T,A);
A_at_Temp = A_F(Temps);
Beta_F = griddedInterpolant(T,Beta);
Beta_at_Temp = Beta_F(Temps);


figure; plot(T,A,'xb');hold on; plot(Temps,A_at_Temp,'--b'); hold on;

end

function Sy_CoV =  Sy_R66_Max_CoV(ConfFactor)

% Finding the coefficient of variation for Sy from R66 fits
Temps = [20:1:700];
Sy_R66_Mean = 237.84.*(1 - 2.2628e-3 .* (Temps - 20) + 4.134e-6 .*(Temps - 20).^2 ...
    - 2.7745e-9.*(Temps - 20).^3);

Sy_R66_LB = 179.48*(1.1*(1 - 2.2628e-3.*(Temps - 20) + 4.134e-6.*(Temps - 20).^2 ...
    - 2.7745e-9.*(Temps - 20).^3)-0.1);

% ConfLimit = 0.95;
% ConfFactors = norminv([(1-ConfLimit)/2 1-(1-ConfLimit)/2]);
% ConfFactor = (ConfFactors(2)-ConfFactors(1))/2;

Sy_R66_STD = (Sy_R66_Mean - Sy_R66_LB)./ConfFactor;

Max_CoV = max(Sy_R66_STD./Sy_R66_Mean);

Sy_CoV = Max_CoV;

end

function Alpha_at_Temp = Thermal_Expansion_Lookup(Temps)

Mean_Alpha = (8.39e-03 .*Temps + 1.53e+01).*10^(-6); % R66, Section 2, Figure 2.35

Alpha_at_Temp = Mean_Alpha;

end

function [Sy_at_Temp,Ks_at_Temp] = Tensile_Properties_Lookup(Temps)


T =    [20 353.5 358.9 444.4 505.9 525.0 529 532 539 542 554 554.7];
Sy = [266.2 182.8 182.6 177.6 171.9 167.5 166.6 165.9 164.3 163.6 160.8 160.7];
Ks = [0.752 1.350 1.350 1.350 1.338 1.300 1.292 1.286 1.272 1.266 1.242 1.241];


Sy_F = griddedInterpolant(T,Sy);
Sy_at_Temp = Sy_F(Temps);

Ks_F = griddedInterpolant(T,Ks);
Ks_at_Temp = Ks_F(Temps);

% figure; plot(Temps,Sy_Mean,'-k'); hold on;
%  plot(Temps,Sy_LB,'--k'); hold on;
%  plot(Temps,Sy_at_Temp,'-r')

end

function [Zeta_Mean,Zeta_STD] = DefineZetaP(ConfFactor)

Zeta_Mean = 0.552;
Zeta_LB = -0.2808;
Zeta_UB = 1.68;

Zeta_STD = max(abs(Zeta_Mean - Zeta_LB), abs(Zeta_Mean - Zeta_UB))./ConfFactor;

end


%% Scripts for preparing permutations and bins

function [LHS,Corr_Error] = Correlated_Bins(LHS,Param_No_1,Param_No_2,Input_Correlation)

p1 = LHS(:,Param_No_1);
p2 = LHS(:,Param_No_2);

u = copularnd('Gaussian',Input_Correlation,length(p1));

[s1,i1] = sort(u(:,1));
[s2,i2] = sort(u(:,2));

x1 = zeros(size(s1));
x2 = zeros(size(s2));

x1(i1) = sort(p1);
x2(i2) = sort(p2);

Out_Correlation_Matrix = corr([x1,x2] ,'Type','spearman');

Corr_Error = Input_Correlation- Out_Correlation_Matrix(1,2);

LHS(:,Param_No_1) = x1;
LHS(:,Param_No_2) = x2;

end

function LHS = LHS_Permutations(Nb,Nv)

LHS = zeros(Nb,Nv);
for V = 1:Nv
    rng('shuffle');
    LHS(:,V) = randperm(Nb)';
end

end


function LHS_Hist_Samples = Histogram_LHS(Data,LHS_No_Bins)

%% Creating a histogram

H = histogram(Data);

% Saving the data

All_Data = Data;
Min_Max = [min(Data) max(Data)];
Histogram_X = H.BinEdges(1:end-1) + H.BinWidth;
Histogram_Freq = H.Values./length(Data);
Histogram_N_Count = H.Values;


%% Finding the mode value
[~,Inx_Mode] = max(Histogram_N_Count );
Histogram_Mode = Histogram_X(Inx_Mode);

%% Finding the median value:
Sorted_Data = sort(Data);
Histogram_Median = Sorted_Data(round(length(Data)./2));

%% Finding the 98% Confidence Intervals:
Conf_Level = 98;

[~,Inx_Upper_CI] = min(abs(cumsum(Histogram_Freq) - Conf_Level./100));
[~,Inx_Lower_CI] = min(abs(cumsum(Histogram_Freq) - (100 - Conf_Level)./100));

Histrogram_CIs.Confidence_Level = [num2str(Conf_Level) '%'];
Histrogram_CIs.Upper_Lower_CIs = ...
    [Histogram_X(Inx_Upper_CI) Histogram_X(Inx_Lower_CI)];



Levels = linspace(0.0001,0.99999,LHS_No_Bins-2);

LHS_Hist_Samples = [min(Data);...
    Sorted_Data(round(length(Data).*Levels));...
    max(Data)];

% figure; histogram(Data,round(LHS_No_Bins.^0.5),'Normalization','probability'); hold on; histogram(LHS_Samples,round(LHS_No_Bins^0.5),'Normalization','probability')

end


%% Scripts for collating the history data into array formate for later use in Probabilistic assessment

function [ArrayInputData,Dwell_Times,Modes,CycleEventNo,Tilts] = PrepareHistoryData(Repeat_History_Data_Analysis)

Event_Max_Duration = 100;
EventTiltAssumption = 'Mean_Tilts';

if Repeat_History_Data_Analysis
    History_Summary_Events_V2(Event_Max_Duration,EventTiltAssumption)  
end


InputData = PreAssessment_V4(Repeat_History_Data_Analysis,EventTiltAssumption);

ArrayInputData = CollateArrayInputData(InputData);

Dwell_Times = ArrayInputData(:,end-1);
Modes = ArrayInputData(:,end);
CycleEventNo = ArrayInputData(:,1);
Tilts = ArrayInputData(:,40);

% Some cleaning just to ensure the tilt data is realistic:
Tilts = CleanTilts(Tilts,ArrayInputData,Modes);


end

function All_Input_Data = CollateArrayInputData(InputData)

All_Input_Data = [];

for C = 1:InputData.NumberCycles
    
    if InputData.CycleEvent{C}.NumberEvents ~= 0
        E =  [1:InputData.CycleEvent{C}.NumberEvents]';
        Years =  InputData.CycleEvent{C}.Years;
        TubesSteamTemps = InputData.CycleEvent{C}.TubesSteamTemps;
        Tilts = InputData.CycleEvent{C}.Tilts;
        Durations = InputData.CycleEvent{C}.Durations;
        Modes = InputData.CycleEvent{C}.Modes;
        
        All_Input_Data = vertcat(All_Input_Data,[E Years TubesSteamTemps Tilts Durations Modes]);
        All_Input_Data = vertcat(All_Input_Data,zeros(1,42));
        
    end
end

end

function Asmt_Tilts = CleanTilts(Tilts,ArrayInputData,Modes)

%% Checking if the tilts make sense

All_Tubes_Temps = ArrayInputData(:,(1:37)+2);

Max_Temps = max(All_Tubes_Temps,[],2);
Min_Temps = min(All_Tubes_Temps,[],2);

OrignalTilts = Tilts; % These are the tilts from the original raw data spreadsheets
Calculated_Tilts = Max_Temps - Min_Temps; % These are the tilts I calcualte after the 'make up' the temperauture readings for uninstrumented tubes

Asmt_Tilts = zeros(size(Modes));

% 1. If the orginal tilts are present (from the raw spreadsheets) then use those
Asmt_Tilts(Modes~=0) = OrignalTilts(Modes~=0);

% 2. If some of the Tilts are missing or corrupted use the tilts I calcualted (which are typically larger than the original ones)
Asmt_Tilts(isnan(Asmt_Tilts)) = Calculated_Tilts(isnan(Asmt_Tilts));

% 3. Tilts for shutdowns are set to zero, it doesn't really matter for damage
Asmt_Tilts(Modes==0) = 0;

% 4. Capping the min tilt to 10 degrees
Asmt_Tilts(Asmt_Tilts<10) = 10;

% 5. Rouding up for each of use later in the probabilistic code
Asmt_Tilts = ceil(Asmt_Tilts);

% 6. The original data was capped at around 194
Asmt_Tilts(Asmt_Tilts>194) = 194;

% figure, whitebg('w'); set(gcf,'color','w');
%
%    histogram(Asmt_Tilts(Modes~=0),'Normalization','probability'); hold on;
%     xlabel('Historic tilt/[�C]'); ylabel('Frequency');
%     set(gca,'FontSize',16,'fontWeight','bold');
%     set(findall(gcf,'type','text'),'fontSize',16,'fontWeight','bold');
%     set(gca,'LineWidth',2);
%     set(gcf,'pos',[250 100 1500 600])
%     grid on;

end


