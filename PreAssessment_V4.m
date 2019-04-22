function Prob_Asmt_Input_Data = PreAssessment_V4(Repeat_Analysis,EventTiltAssumption)


if ~Repeat_Analysis
    
    load('Prob_Asmt_Input_Data.mat')

else
    
    %% Input data for assessment
    
    Years = [1984:2007 2009:2014];
    
    History_Data.Years = [];
    History_Data.RawSteamTemps = [];
    History_Data.MaxTemps = [];
    History_Data.Tilts = [];
    History_Data.Durations = [];
    History_Data.Modes = [];
    
    for Year = Years
        %% Reading the summarised evnets' data based on the original cycle counting
        Annual_Summary_Events{Year} = csvread(['Har_R2_2C1_Summary_Events_' num2str(Year) '_NewEvents_' EventTiltAssumption '.csv']);
        
%         Annual_Summary_Events{Year} = csvread(['Har_R2_2C1_Summary_Events_' num2str(Year) '.csv']);
        
        History_Data.Years = vertcat(History_Data.Years,ones(length(Annual_Summary_Events{Year}(:,53)),1).*Year);
        History_Data.RawSteamTemps = vertcat(History_Data.RawSteamTemps,Annual_Summary_Events{Year}(:,1:50));
        History_Data.MaxTemps = vertcat(History_Data.MaxTemps,Annual_Summary_Events{Year}(:,52));
        History_Data.Tilts = vertcat(History_Data.Tilts,Annual_Summary_Events{Year}(:,53));
        History_Data.Durations = vertcat(History_Data.Durations,Annual_Summary_Events{Year}(:,end));
        History_Data.Modes = vertcat(History_Data.Modes,Annual_Summary_Events{Year}(:,end-1));
    end
    
    
    %% Procedure for getting temps for each of the 37 based on the 50 raw measurements available
    History_Data = TempsPerTube(History_Data);
    
    %% Deviding the history data into cycles
    
    IndxShutdown = find(History_Data.Modes == 0);
    
    % Assume each year will have a whole number of cycles (not true because some cycles might start duirng one year and end the following)
    if IndxShutdown(end) ~= length(History_Data.Modes)
        IndxShutdown = [IndxShutdown;length(History_Data.Modes)];
    end
    
    % Taking note of the number of cycles
    History_Cycles_Data.NumberCycles = length(IndxShutdown) - 1;
    
    for i = 1:length(IndxShutdown)-1
        
        Cycle_No = i;
        
        History_Cycles_Data.CycleEvent{Cycle_No}.NumberEvents = length(History_Data.Years(IndxShutdown(i)+1:IndxShutdown(i+1)-1,:));
        History_Cycles_Data.CycleEvent{Cycle_No}.Years = History_Data.Years(IndxShutdown(i)+1:IndxShutdown(i+1)-1,:);
        History_Cycles_Data.CycleEvent{Cycle_No}.TubesSteamTemps = History_Data.TubeTemps(IndxShutdown(i)+1:IndxShutdown(i+1)-1,:);
        History_Cycles_Data.CycleEvent{Cycle_No}.Tilts = History_Data.Tilts(IndxShutdown(i)+1:IndxShutdown(i+1)-1,:);
        History_Cycles_Data.CycleEvent{Cycle_No}.Durations = History_Data.Durations(IndxShutdown(i)+1:IndxShutdown(i+1)-1,:);
        History_Cycles_Data.CycleEvent{Cycle_No}.Modes = History_Data.Modes(IndxShutdown(i)+1:IndxShutdown(i+1)-1,:);
        
    end
    
    
    Prob_Asmt_Input_Data = History_Cycles_Data;
    
    save('Prob_Asmt_Input_Data.mat','Prob_Asmt_Input_Data')
    
end



end



function History_Data = TempsPerTube(History_Data)

%% Row and Tube numbering
% Configuratoin of tubes and rows (50 data colomns in order of appearance in raw temperature data files) for HAR Reactor 2 Pod 2C1 Header 4:
Header_4_Raw_Tube_Order = xlsread('HAR_R2_2C1_H4_Raw_Tubes.xlsx');
Header_1_Raw_Tube_Order = xlsread('HAR_R2_2C1_H1_Raw_Tubes.xlsx');

% Configuratoin of tubes and rows (37 holes in order of appearance in abaqus input file) for HAR Reactor 2 Pod 2C1 Header 4:
HAR_R2_2C1_H4_Raw_Tube_Conf = xlsread('HAR_R2_2C1_H4_Raw_Tube_Conf.xlsx');



%% Collacting two matricies (one per instrumented header) including tube rOw, number and measured temperature
% Data order: [ROW TUBE (TEMPS_DATA)]

Header_4_Available_Temps =  horzcat(Header_4_Raw_Tube_Order,History_Data.RawSteamTemps(:,1:19)');

% Order the available data for Header 4 in terms of tube number
[~,I] = sort(Header_4_Raw_Tube_Order(:,2));
Header_4_Available_Temps = Header_4_Available_Temps(I,:);


%% Procedure for allocating tube temperatures

for Event_No = 1:length(History_Data.Years)
    
    All_Avelable_Temps =  horzcat(vertcat(Header_4_Raw_Tube_Order,Header_1_Raw_Tube_Order),History_Data.RawSteamTemps(Event_No,:)'); % Order: Row/Tube/Temperature
    
    
    % Checking for instances where all measurments are missing
    if sum(isnan(All_Avelable_Temps(:,3))) == 50 || sum(All_Avelable_Temps(:,3)>1000) == 50
        All_Avelable_Temps(:,3) = ones(size(All_Avelable_Temps(:,3))) .* History_Data.MaxTemps(Event_No);
        % Special case for shutdown:
        if History_Data.MaxTemps(Event_No) == 0 && History_Data.Modes(Event_No) == 0
            All_Avelable_Temps(:,3) = ones(size(All_Avelable_Temps(:,3))) .* TempStress_Deterministic(History_Data.Modes(Event_No));
        end
        
    end
    
    % Finding the average temperatuers for each row
    Row_Temp_Avg = Average_Row_Temperatures(All_Avelable_Temps);
    
    % For missing rows use an extrapolation between adjacent rows
    Row_Temp_Avg = Extrapolate_Missing_Temps(Row_Temp_Avg);
    
    % 1. Assign the data already available for Header 4
    
    TubeTemps{Event_No} = horzcat(HAR_R2_2C1_H4_Raw_Tube_Conf,zeros(length(HAR_R2_2C1_H4_Raw_Tube_Conf),1));
    
    for Tube_No = 1:length(TubeTemps{Event_No})
        for ii = 1:size(Header_4_Available_Temps,1)
            if TubeTemps{Event_No}(Tube_No,2) == Header_4_Available_Temps(ii,2) % Assigning the temperatures by tube number
                I = find(Header_4_Available_Temps(:,2)== Header_4_Available_Temps(ii,2));
                TubeTemps{Event_No}(Tube_No,3) =  Header_4_Available_Temps(I,Event_No+2);
            end
        end
    end
    
    % 2. For non-instrumented holes use an average of temperatures based on rows. These row temperature measurements will come for either Header 4 or Header 1 measurements.
    
    TubeTemps{Event_No}(isnan(TubeTemps{Event_No}(:,3)),3) = 0; % replacing the NaN fields with 0 for ease later
    
    Ind_Missing_Temps = find(TubeTemps{Event_No}(:,3)==0);
    
    for i = 1:length(Ind_Missing_Temps)
        TubeTemps{Event_No}(Ind_Missing_Temps(i),3) = Row_Temp_Avg(TubeTemps{Event_No}(Ind_Missing_Temps(i),1),2);
    end
    
    
    % 3. Replacing dodgy measurements with max temps 
    
    if max(TubeTemps{Event_No}(:,3)') > 1000 
       TubeTemps{Event_No}(:,3) = History_Data.MaxTemps(Event_No);
    end
    
    % Saving the processed data
    History_Data.TubeTemps(Event_No,:) = TubeTemps{Event_No}(:,3)';
 
end

end


function Row_Temp_Avg = Average_Row_Temperatures(All_Avelable_Temps)

% Finding the average temperatuers for each row

Row_Temp_Avg = zeros(19,2); % First colomn is the row number and the second is the average temperautre
Row_Temp_Avg(:,1) = 1:19;

for i = 1:length(Row_Temp_Avg)
    Row_Temps = All_Avelable_Temps(All_Avelable_Temps(:,1)==i,3);
    Row_Temps = Row_Temps(isnan(Row_Temps)==0);
    Row_Temp_Avg(i,2) = mean(Row_Temps);
end

end

function Row_Temp_Avg = Extrapolate_Missing_Temps(Row_Temp_Avg)

% First stage: check the first and last rows:
N = 0;
i = 1;
while isnan(Row_Temp_Avg(i,2))
    N = N+1;
    Row_Temp_Avg(i:(i+N-1),2) = Row_Temp_Avg(i+N,2);
end

N = 0;
i = 19;
while isnan(Row_Temp_Avg(i,2))
    N = N+1;
    Row_Temp_Avg((i-N+1):i,2) = Row_Temp_Avg(i-N,2);
end

% Second stage: examin the intermidiate rows between the first and last rows
Ind_Missing_Temps = find(isnan(Row_Temp_Avg(:,2))==1);

if isempty(Ind_Missing_Temps) == 0
    for i = Ind_Missing_Temps'
        
        Temp_1 = Row_Temp_Avg(i-1,2);
        Temp_2 = Row_Temp_Avg(i+1,2);
        
        N_1 = 0;
        N_2 = 0;
        
        while isnan(Temp_1)
            N_1= N_1+1;
            Temp_1 = Row_Temp_Avg(i-1-N_1,2);
        end
        
        while isnan(Temp_2)
            N_2= N_2+1;
            Temp_2 = Row_Temp_Avg(i+1+N_2,2);
        end
        
        Ind_1 = Row_Temp_Avg(i-1-N_1,1);
        Ind_2 = Row_Temp_Avg(i+1+N_2,1);
        
        Row_Temp_Avg(i,2) = Temp_1  + (i-Ind_1) .* ((Temp_2 - Temp_1)./(Ind_2 - Ind_1));
    end
else
    Row_Temp_Avg = Row_Temp_Avg;
end
end



function [Temp,Event_Str_Components] = TempStress_Deterministic(Mode)


switch Mode % Taken from Page 64 of M.Stevens report
    case 0 % Cold shutdown
        Event_Str_Components = [0 0 0 0 0 0 ];
        Temp = 20;
    case 1 % Mode 1: 525-540°C - >60°C
        Event_Str_Components = [32.2 221.7 -13 -75.4 5.4 6.5];
        Temp = 529.0;
    case 2 % Mode 2: 540-550°C - >60°C
        Event_Str_Components = [32.2 221.7 -13 -75.4 5.4 6.5];
        Temp = 539.0;
    case 3 % Mode 3: 550-565°C - >60°C
        Event_Str_Components = [32.2 221.7 -13 -75.4 5.4 6.5];
        Temp = 554.0;
    case 4 % Mode 4: 565-575°C - >60°C
        Event_Str_Components = [66.9 374.3 -10.1 -129.1 9.4 10.4];
        Temp = 554.7;
    case 5 % Mode 0/5: '400-525°C - >60°C'
        Event_Str_Components = [26.1 195 -13.5 -66 4.7 5.8];
        Temp = 514.6;
    case 6 % Normal 1: '525-540°C - <60°C'
        Event_Str_Components = [20 168.2 -14.1 -56.5 4 5.1];
        Temp = 532.0;
    case 7 % Normal 2: 540-550°C - <60°C
        Event_Str_Components = [20 168.2 -14.1 -56.5 4 5.1];
        Temp = 542.0;
    case 8 % Normal 0/3: 400-525°C - <60°C
        Event_Str_Components = [20 168.2 -14.1 -56.5 4 5.1];
        Temp = 516.1;
end

end