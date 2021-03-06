

######################################
#Global Fishery Recovery Wrapper--------------------------------------------------
# This code executes the steps in the Global Fishery Recovery program
######################################


# Source Functions --------------------------------------------------------

sapply(list.files(
  pattern = "[.]R$",
  path = "Functions",
  full.names = TRUE
),
source)

# Read in and process data ------------------------------------------------------------

if (RunAnalyses == TRUE)
{
  textfiles <- list.files(pattern = '.txt')
  if (length(textfiles) > 0)
  {
    unlink(textfiles)
  }
  
  if (file.exists(paste(ResultFolder, 'Cleaned Compiled Database.csv', sep =
                        '')) == F)
  {
    #     source('Database_Build.R') #Build Tyler's database
    
    fulldata <- DatabaseBuild()
    
    Spec_ISSCAAP = read.csv("Data/ASFIS_Feb2014.csv", stringsAsFactors =
                              F) # list of ASFIS scientific names and corressponding ISSCAAP codes
    
    Spec_Region_RAM = read.csv('Data/Ram_Regions_031115.csv', stringsAsFactors =
                                 F) # list of RAM Assessed IDs previously matched to species code and FAO Region
    
    Spec_Region_RAM$RegionFAO <-
      gsub("/", ",", Spec_Region_RAM$RegionFAO, fixed = T) # change / to , for use in string parsing during filtering function
    
    if (custom_phi == T)
    {
      taxdata <-
        read.csv('Data/asfis_2015_taxonomy.csv', stringsAsFactors = F)
      
      phidata <-
        read.csv('Data/thorson_2012_msy_ratios.csv', stringsAsFactors = F)
      
      fulldata <-
        assign_phi(fulldata,
                   taxdata,
                   phidata,
                   default_phi = DefaultPhi,
                   min_phi = -1)
    }
    if (custom_phi == F)
    {
      fulldata$phi <- DefaultPhi
    }
    
    CSids <- FindCatchShares(DataR = fulldata, CatchSharePercent = 50)
    
    fulldata$CatchShare[fulldata$IdOrig %in% CSids] <- 1
    
    write.csv(file = paste(ResultFolder, "fulldata.csv", sep = ""), fulldata)
    
    show('Done building raw database')
    
    RawData <- fulldata
    
    RawData$FvFmsy <- RawData$UvUmsytouse
    
    FullData <- fulldata
    
    ### TEMPORARY ###
    
    FullData <-
      FullData[!(FullData$IdOrig %in% c('SEFSC-RSNAPGM-1872-2011-HIVELY')), ] # GoMex Red Snapper
    
    if ((is.numeric(SubSample) && SubSample > 0))
    {
      FaoIds <- unique(FullData$IdOrig[FullData$Dbase == 'FAO'])
      
      SampleIds <-
        sample(FaoIds, SubSample * length(FaoIds), replace = FALSE)
      # # #
      FullData <-  FullData[!(FullData[, IdVar] %in% SampleIds), ]
    }
    
    if (is.character(SubSample))
    {
      FaoIds <-
        FullData$IdOrig[(FullData$Country %in% SubSample) &
                          FullData$Dbase == 'FAO']
      
      FullData <-
        FullData[FullData$Dbase == 'RAM' |
                   ((FullData$Country %in% SubSample) & FullData$Dbase == 'FAO'), ]
    }
    
    FullData$FvFmsy <- FullData$UvUmsytouse
    
    rm(fulldata)
    
    FullData <-
      RamSciNameAdjuster(FullData, VersionToUse = 'SciNameToUse') # adjust SciNames of RAM stocks that have synonyms and other variations not found in AFSIS list

    CleanedData <-
      MaidService(FullData, OverlapMode, BaselineYear) #Filter out unusable stocks, prepare data for regression and use
    
    DroppedStocks <- CleanedData$DroppedStocks
    
    StitchIds <- CleanedData$StitchIds
    
    FullData <- CleanedData$CleanedData
    
    AllOverlap <- CleanedData$AllOverlap
    
    MultinationalOverlap <- CleanedData$MultinationalOverlapIds
    
    FullData <-
      RamSciNameAdjuster(FullData, VersionToUse = 'scientificname') # adjust SciNames of RAM stocks back to original names for FindFishbase
    
    FullData <- FindFishbase(FullData)
    
    FullData <- FindResilience(FullData)
    
    write.csv(file = paste(ResultFolder, 'Cleaned Compiled Database.csv', sep =
                             ''),
              FullData)
    
    write.csv(file = paste(ResultFolder, 'Omitted Stocks.csv', sep = ''),
              DroppedStocks)
    
    write.csv(file = paste(ResultFolder, 'Raw Database.csv', sep = ''), RawData)
  }
  else
  {
    FullData <-
      read.csv(paste(ResultFolder, 'Cleaned Compiled Database.csv', sep = ''),
               stringsAsFactors = F)
    
    RawData <-
      read.csv(paste(ResultFolder, 'Raw Database.csv', sep = ''),
               stringsAsFactors = F)
    
  }
  
  FullData$ReferenceBiomass[FullData$ReferenceBiomass == 0] <- NA
  
  ModelNames <-
    names(Regressions) #Create columns to store the results of each PRM
  
  for (m in 1:length(ModelNames))
  {
    eval(parse(text = paste(
      'FullData$', ModelNames[m], 'Marker<- FALSE', sep = ''
    )))
    
    eval(parse(text = paste(
      'FullData$', ModelNames[m], 'Prediction<- NA', sep = ''
    )))
  }
  
  SofiaData <-  FullData[FullData$Dbase == 'SOFIA', ]
  
  RamData <- FullData[FullData$Dbase == 'RAM', ]
  
  FaoData <- FullData[FullData$Dbase == 'FAO', ]
  
  show('Raw Data Processed')
  
  show('Data prepared for regression')
  
  # Rprof(NULL)
  #  RProfData<- readProfileData('Rprof.out')
  #  flatProfile(RProfData,byTotal=TRUE)
  
  # Run regressions ---------------------------------------------------------
  RegressionResultsAllRam <-
    RunRegressions(RamData, Regressions, 'Real Stocks') # run regressions using all RAM stock values
  
  RamData <-
    RegressionResultsAllRam$RamData # retain all RamData, not just the RamData with assesment only value
  
  RealModels <-
    RegressionResultsAllRam$Models # use regression models estimated from assessment BvBmsy values only
  
  ModelFitIds <-
    RamData$IdOrig[grepl('-est-', RamData$BvBmsyUnit)] # find stock ids with model fit BvBmsy values
  
  RegressionResults <-
    RunRegressions(RamData[!(RamData$IdOrig %in% ModelFitIds), ], Regressions, 'Real Stocks') # run regressions using assesment BvBmsy values only
  
  if (RegressAllRam == FALSE)
  {
    RealModels <-
      RegressionResults$Models # use regression models estimated from assessment BvBmsy values only
  }
  
  RealModelFactorLevels <- NULL
  
  Models <- names(Regressions)
  
  show('Regressions Run')
  
  # Process Regressions -----------------------------------------------------
  
  ## Determine species category levels that were used in each model run
  
  TempOmitted <- NULL
  for (m in 1:length(names(Regressions)))
  {
    Model <- names(Regressions)[m]
    eval(parse(
      text = paste(
        'RealModelFactorLevels$',
        Model,
        '<- RealModels$',
        Model,
        '$xlevels$SpeciesCatName',
        sep = ''
      )
    ))
  }
  
  #   RamData<- InsertFisheryPredictions(RamData,RealModels) #Add fishery predictions back into main dataframe
  
  if (RegressAllRam == TRUE)
    # generate SDevs depending on whether regression was run all all ram data or just assessment values
  {
    RealModelSdevs <- CreateSdevBins(RealModels, RamData, TransbiasBin)
  }
  
  if (RegressAllRam == FALSE)
  {
    RealModelSdevs <-
      CreateSdevBins(RealModels, RegressionResults$RamData, TransbiasBin)
  }
  
  save(RealModels,
       RealModelSdevs,
       file = paste(ResultFolder, 'PrmRegressions.Rdata', sep = ''))
  
  
  # Prepare data for regression application ---------------------------------
  
  WhereFaoNeis <-
    (grepl('nei', FaoData$CommName) |
       grepl('spp', FaoData$SciName)) &
    grepl('not identified', FaoData$SpeciesCatName) == F #Find unassessed NEIs
  
  WhereFaoMarineFish <-
    grepl('not identified', FaoData$SpeciesCatName)
  
  FaoSpeciesLevel <-
    FaoData[WhereFaoNeis == F &
              WhereFaoMarineFish == F , ] #Fao stocks named to the species level
  
  FaoNeiLevel <-
    FaoData[WhereFaoNeis, ] #fao species named to the nei or spp level
  
  FaoMarineFishLevel <-
    FaoData[WhereFaoMarineFish, ] #completely unidentified marine goo
  
  TempLevel <- NULL
  
  TempModel <- NULL
  
  show('Regressions Processed')
  
  # Prep for dummy species categories  ----------------------------------------
  
  AllPossible <-
    unique(data.frame(I(FullData$SpeciesCatName), I(FullData$SpeciesCat)))
  
  colnames(AllPossible) <- c('SpeciesCatName', 'SpeciesCat')
  
  RamPossibleCats <- unique(RamData$SpeciesCatName)
  
  FaoSpeciesPossibleCats <- unique(FaoSpeciesLevel$SpeciesCatName)
  
  FaoNeiPossibleCats <- unique(FaoNeiLevel$SpeciesCatName)
  
  FaoMarineFishPossibleCats <-
    unique(FaoMarineFishLevel$SpeciesCatName)
  
  
  # Apply regressions -------------------------------------------------------
  
  Models <- Models[Models != 'M7']
  
  for (m in 1:length(Models))
    #Apply models to species level fisheries
  {
    TempModelName <- Models[m]
    
    eval(parse(
      text = paste('TempLevel<- RealModelFactorLevels$', TempModelName, sep =
                     '')
    ))
    
    eval(parse(text = paste(
      'TempModel<- RealModels$', TempModelName, sep = ''
    )))
    
    ProxyCats <-
      AssignNearestSpeciesCategory(FaoSpeciesLevel, TempLevel, AllPossible)
    
    Predictions <- predict(TempModel, ProxyCats$Data)
    
    eval(parse(
      text = paste(
        'FaoSpeciesLevel$',
        TempModelName,
        'Prediction<- Predictions',
        sep = ''
      )
    ))
  }
  
  #   TempLevel<- NeiModelFactorLevels$M6
  #
  #   ProxyCats<- AssignNearestSpeciesCategory(FaoNeiLevel,TempLevel,AllPossible)$Data
  #
  #   Predictions<- predict(NeiModels$M6,ProxyCats) #Apply nei model
  #
  FaoNeiLevel$M6Prediction <- 999
  
  FaoMarineFishLevel$M7Prediction <- 999
  
  show('Regressions Applied')
  
  # Assign and identify best predicted biomass to stocks  ---------------------------------------
  
  
  # HasAllRefs<- ddply(RamData,c('IdOrig'),summarize,HasAllBFM=any(is.na(BvBmsy)==F & is.na(FvFmsy)==F & is.na(MSY)==F))
  
  HasAllRefs <- RamData %>%
    group_by(IdOrig) %>%
    summarize(HasAllBFM = any(is.na(BvBmsy) == F &
                                is.na(FvFmsy) == F & is.na(MSY) == F)) %>%
    ungroup()
  
  RamData <-
    RamData[RamData$IdOrig %in% HasAllRefs$IdOrig[HasAllRefs$HasAllBFM == T], ]
  
  # Arg<- ddply(RamData,c('IdOrig'),summarize,HasFinalF=any(is.na(FvFmsy)==F & is.na(BvBmsy)==F & is.na(MSY)==F & Year==2011))
  
  MissingF <- is.na(RamData$FvFmsy) & RamData$Year == BaselineYear
  
  RamData$FvFmsy[MissingF] <-
    (RamData$Catch[MissingF] / RamData$MSY[MissingF]) / RamData$BvBmsy[MissingF]
  
  #For now, solve for F/Fmsy in BaselineYear, ask Hiveley about this though. Check whether you always have B/Bmsy and MSY and Catch in BaselineYear
  
  if (IncludeNEIs == TRUE)
  {
    PredictedData <-
      rbind(RamData,
            SofiaData,
            FaoSpeciesLevel,
            FaoNeiLevel,
            FaoMarineFishLevel) #Bind all data back together
  }
  if (IncludeNEIs == FALSE)
  {
    PredictedData <-
      rbind(RamData, SofiaData, FaoSpeciesLevel) #Bind all data back together
  }
  BiomassColumns <-
    (grepl('BvBmsy$', colnames(PredictedData)) |
       grepl('Prediction', colnames(PredictedData))) &
    grepl('LogBvBmsy', colnames(PredictedData)) == F
  
  BioNames <- colnames(PredictedData)[BiomassColumns]
  
  HasBiomass <-
    rowSums(is.na(PredictedData[, BiomassColumns])) < length(BioNames)
  
  BiomassData <-
    PredictedData[HasBiomass, ] #Only store fisheries that have some form of biomass estimates
  
  MissingData <-
    PredictedData[HasBiomass == F & PredictedData$Dbase == 'FAO', ]
  
  AvailableBio <- (BiomassData[, BiomassColumns])
  
  AvailableBioMarker <-
    matrix(rep((1:dim(AvailableBio)[2]), dim(AvailableBio)[1]),
           dim(AvailableBio)[1],
           dim(AvailableBio)[2],
           byrow = TRUE)
  
  AvailableBioMarker <- AvailableBioMarker * (is.na(AvailableBio) == F)
  
  AvailableBioMarker[AvailableBioMarker == 0] <- NA
  
  BestModel <- apply(AvailableBioMarker, 1, min, na.rm = T)
  
  BestBio <- NULL
  for (b in 1:dim(AvailableBio)[1])
  {
    BestBio[b] <- AvailableBio[b, BestModel[b]]
  }
  
  BestBio[BestModel == 1] <- log(BestBio[BestModel == 1])
  
  BestModelnames <- c('RAM', ModelNames)
  
  BestModelNames <- BestModelnames[sort(unique(BestModel))]
  
  BestModel <- as.factor((BestModel))
  
  levels(BestModel) <- BestModelNames
  
  BiomassData$BestModel <- BestModel
  
  BiomassData$BvBmsy <- BestBio
  
  BiomassData$PRMBvBmsy <- BestBio
  
  #   BiomassData$CommName<- as.character((BiomassData$CommName))
  
  BiomassData$SciName <- as.character((BiomassData$SciName))
  
  BiomassData$SpeciesCatName <-
    as.character(BiomassData$SpeciesCatName)
  
  WhereNeis <-
    (grepl('nei', BiomassData$CommName) |
       grepl('spp', BiomassData$SciName)) &
    grepl('not identified', BiomassData$SpeciesCatName) == F &
    (BiomassData$Dbase == 'FAO') #Find unassessed NEIs
  
  WhereUnidentified <-
    grepl('not identified', BiomassData$SpeciesCatName)
  
  WhereSpeciesLevel <-
    WhereNeis == F &
    WhereUnidentified == F #Fao stocks named to the species level
  
  BiomassData$IdLevel[WhereNeis] <- 'Neis'
  
  BiomassData$IdLevel[WhereUnidentified] <- 'Unidentified'
  
  BiomassData$IdLevel[WhereSpeciesLevel] <- 'Species'
  
  #   BiomassData<- AssignEconomicData(BiomassData) #Assign price and cost data to each stock
  
  BiomassData$Price <-
    NA # Price and BvBmsyOpenAccess variable must be created before Analyze fisheries. Will be filled later by Assign EconData
  
  BiomassData$BvBmsyOpenAccess <- NA
  
  BiomassData$RanCatchMSY <- F
  
  show('Results Processed')
  
  # Run First Analisis of Current Status --------------------------------------------------
  
  BiomassData$CatchMSYBvBmsy_LogSd <- NA
  
  GlobalStatus <-
    AnalyzeFisheries(
      BiomassData,
      'Baseline Global Status',
      'Year',
      min(BiomassData$Year):max(BiomassData$Year),
      RealModelSdevs,
      NeiModelSdevs,
      TransbiasBin,
      TransbiasIterations
    )
  
  #   RAMStatus<- AnalyzeFisheries(BiomassData[BiomassData$Dbase=='RAM',],'RAM Status','Year',1950:2010,RealModelSdevs,NeiModelSdevs,TransbiasBin,TransbiasIterations)
  
  # Calculate MSY -----------------------------------------------------------
  
  sigR <- 0
  
  GlobalStatus$Data$BvBmsySD[GlobalStatus$Data$Dbase == 'SOFIA'] <-
    0.1
  
  
  #   missing <- read.csv('Fish missing from phi.csv')
  #   colnames(missing) <- c('nothing','IdOrig')
  # #   (GlobalStatus$Data)
  
  #   huh <- GlobalStatus$Data[GlobalStatus$Data$IdOrig %in% missing$IdOrig,]
  
  samples = sample(GlobalStatus$Data$IdOrig, 10)
  
  CatchMSYresults <-
    (
      GlobalStatus$Data %>% 
        # filter(IdOrig %in% samples) %>% 
      RunCatchMSY(
        ErrorSize,
        sigR,
        Smooth,
        Display,
        BestValues,
        ManualFinalYear,
        NumCatchMSYIterations,
        NumCPUs,
        CatchMSYTrumps
      )
    )
  
  show("Completed CatchMSY")
  
  CatchMSYPossibleParams <- CatchMSYresults$PossibleParams
  
  MsyData <- CatchMSYresults$MsyData
  
  # Calculate k and g for RAM stocks
  MsyData$k[MsyData$Dbase == 'RAM'] <-
    (MsyData$Bmsy / MsyData$BtoKRatio)[MsyData$Dbase == 'RAM']
  
  MsyData$g[MsyData$Dbase == 'RAM'] <-
    ((MsyData$MSY * (1 / MsyData$BtoKRatio)) / MsyData$k)[MsyData$Dbase == 'RAM']
  
  MsyData$g[is.na(MsyData$g)] <-
    mean(MsyData$g, na.rm = T) #FIX THIS XXX Apply mean r to fisheries with no r THIS WAS ASSIGNING ALL RAM STOCKS THE MEAN r VALUE
  
  # Adjust MSY of forage fish and RAM stocks with unreliable k estimates (list received from Ray)
  MsyData <- AdjustMSY(Data = MsyData, RawData, ForageFish)
  
  BiomassData$MSY <-
    MsyData$MSY #Assign MSY back to BiomassData estimates
  
  BiomassData$FvFmsy[MsyData$RanCatchMSY == T] <-
    MsyData$FvFmsy[MsyData$RanCatchMSY == T]
  
  BiomassData$BvBmsy[MsyData$RanCatchMSY == T] <-
    log(MsyData$BvBmsy[MsyData$RanCatchMSY == T])
  
  BiomassData$CatchMSYBvBmsy_LogSd[MsyData$RanCatchMSY == T] <-
    (MsyData$CatchMSYBvBmsy_LogSd[MsyData$RanCatchMSY == T])
  
  BiomassData$RanCatchMSY[MsyData$RanCatchMSY == T] <- TRUE
  
  BvBmsyOpenAccess <-
    FindOpenAccess(MsyData, BaselineYear, BOAtol) # find open access equilibrium for each species cat using results in MsyData
  
  BiomassData <-
    AssignEconomicData(BiomassData, BvBmsyOpenAccess) #Assign price and cost data back to each stock in biomass data

  MsyData$PercentGain <- 100 * (MsyData$MSY / MsyData$Catch - 1)
  
  # Run projection analysis -------------------------------------------------
  
  MsyData$Price <- BiomassData$Price
  
  MsyData$BvBmsyOpenAccess <- BiomassData$BvBmsyOpenAccess
  
  MsyData$Price[is.na(MsyData$Price)] <-
    mean(MsyData$Price, na.rm = T) #Apply mean price to fisheries with no price
  
  MsyData$CanProject <-
    is.na(MsyData$MSY) == F &
    is.na(MsyData$g) == F #Identify disheries that have both MSY and r
  
  save(file = paste(ResultFolder, "MsyData.rdata", sep = ""),
       MsyData,
       BiomassData)
  
  MsyData$BestModel <- as.character(MsyData$BestModel)
  
  
  Policies = c(
    'StatusQuoOpenAccess',
    'Opt',
    'CatchShare',
    'StatusQuoFForever',
    'StatusQuoBForever',
    'Fmsy',
    'CloseDown'
  )
  
  FullProjectionData <-
    RunProjection(
      MsyData[MsyData$CanProject == T, ],
      BaselineYear,
      NumCPUs,
      StatusQuoPolicy,
      Policies = Policies,
      Discount = Discount
    ) #Run projections on MSY data that can be projected
  
  PolicyStorage <- FullProjectionData$PolicyStorage
  
  write.csv(file = paste(ResultFolder, 'PolicyStorage.csv', sep = ''),
            PolicyStorage)
  
  ProjectionData <- FullProjectionData$DataPlus
  
  show("Completed Projections")
  if (IncludeNEIs == TRUE)
  {
    #    Rprof()
    Spec_ISSCAAP = read.csv("Data/ASFIS_Feb2014.csv", stringsAsFactors =
                              F) # list of ASFIS scientific names and corressponding ISSCAAP codes
    NeiData <-
      NearestNeighborNeis(
        BiomassData = BiomassData,
        MsyData = MsyData,
        ProjData = ProjectionData,
        BaselineYear = BaselineYear,
        ResultFolder = ResultFolder,
        Spec_ISSCAAP = Spec_ISSCAAP,
        CatchSharePrice = CatchSharePrice,
        CatchShareCost = CatchShareCost,
        NumCPUs = NumCPUs,
        beta = beta
      ) #Run Nearest Neighbor NEI analysis
    
    #     NearestNeighborNeis<- function(BiomassData,MsyData,ProjData,BaselineYear,ResultFolder,Spec_ISSCAAP,
    #                                    CatchSharePrice,CatchShareCost,NumCPUs = 1,beta = 1.3)
    
    #Put NEI stocks back in the appropriate dataframes, remove stocks still missing data
    
    #    Rprof(NULL)
    #     RProfData<- readProfileData('Rprof.out')
    #     flatProfile(RProfData,byTotal=TRUE)
    
    ProjectionData <- bind_rows(ProjectionData, NeiData$ProjNeis)
    
    BiomassData <- bind_rows(BiomassData, NeiData$BiomassNeis)
  }
  
  BiomassData <-
    BiomassData[BiomassData$BvBmsy != 999 &
                  is.infinite(BiomassData$BvBmsy) == FALSE &
                  is.na(BiomassData$BvBmsy) == F, ]
  
  MsyData <- MsyData[is.na(MsyData$MSY) == F, ]
  
  ProjectionData <- ProjectionData[ProjectionData$CanProject == T, ]
  
  ProjectionData$DiscProfits <-
    ProjectionData$Profits * (1 + Discount) ^ -(ProjectionData$Year - BaselineYear)
  
  NoBmsy <- is.na(ProjectionData$Bmsy)
  
  ProjectionData$k[NoBmsy] <-
    ((ProjectionData$MSY / ProjectionData$g) * (1 / ProjectionData$BtoKRatio))[NoBmsy]
  
  ProjectionData$Bmsy[NoBmsy] <-
    (ProjectionData$MSY / ProjectionData$g)[NoBmsy]
  
  ProjectionData$Biomass[is.na(ProjectionData$Biomass) |
                           ProjectionData$Biomass == 0] <-
    (ProjectionData$BvBmsy * ProjectionData$Bmsy)[is.na(ProjectionData$Biomass) |
                                                    ProjectionData$Biomass == 0]
  OriginalProjectionData <- ProjectionData
  
  OriginalFullData <- FullData
  
  OriginalMsyData <- MsyData
  
  OriginalBiomassData <- BiomassData
  
  save.image(file = paste(ResultFolder, 'Global Fishery Recovery Results.rdata', sep =
                            ''))
  
} #Close RunAnalyses If


if (RunAnalyses == F)
  #Load baseline versions of key dataframes for analysis after complete runs
{
  FullData <-
    OriginalFullData #Complete database, post filtering/cleaning etc
  
  BiomassData <- OriginalBiomassData #Fisheries that have B/Bmsy
  
  MsyData <- OriginalMsyData #Fisheries that have B/Bmsy and MSY
  
  ProjectionData <-
    OriginalProjectionData #Fisheries that have B/Bmsy, MSY, and we've run the projections
  
  NoBmsy <- is.na(ProjectionData$Bmsy)
  
  ProjectionData$k[NoBmsy] <-
    ((ProjectionData$MSY / ProjectionData$g) * (1 / ProjectionData$BtoKRatio))[NoBmsy]
  
  ProjectionData$Bmsy[NoBmsy] <-
    (ProjectionData$MSY / ProjectionData$g)[NoBmsy]
  
  ProjectionData$Biomass[is.na(ProjectionData$Biomass) |
                           ProjectionData$Biomass == 0] <-
    (ProjectionData$BvBmsy * ProjectionData$Bmsy)[is.na(ProjectionData$Biomass) |
                                                    ProjectionData$Biomass == 0]
  
}

### Process results and prepare summary tables --------------------------------------------------

### TEMPORARY REMOVAL OF DUPLICATED TUNA STOCKS when using any old data version <6.01 ### !!!!!!!
ProjectionData <- ProjectionData %>%
  filter(!(
    IdOrig %in% c(
      "Lumped-Southern bluefin tuna-FaoRegion51",
      "Lumped-Atlantic bluefin tuna-FaoRegion37",
      "Lumped-Southern bluefin tuna-FaoRegion57",
      "Lumped-Southern bluefin tuna-FaoRegion41",
      "Lumped-Southern bluefin tuna-FaoRegion47",
      "Lumped-Southern bluefin tuna-FaoRegion81"
    )
  ))

# Remove NEIs and forage fish if desired

if (IncludeNEIs == FALSE)
{
  ProjectionData <- ProjectionData[ProjectionData$IdLevel == 'Species', ]
}

if (IncludeForageFish == FALSE)
{
  ProjectionData <-
    ProjectionData[ProjectionData$SpeciesCatName %in% ForageFish == F, ]
}

# Add new "Business as Usual Policies" by combining the results of the respective status quo policies for certain types of stocks, outlined in the function
ProjectionData <-
  BuildPolicyBAUs(
    ProjectionData,
    BaselineYear,
    elastic_demand = elastic_demand,
    elasticity = elasticity,
    Discount = Discount,
    sp_group_demand = sp_group_demand,
    beta = beta
  )

cheat_fig3 <- ProjectionData %>%
  group_by(Policy, Year) %>%
  summarize(
    total_catch = sum(Catch, na.rm = T),
    num_stocks = length(unique(IdOrig)),
    total_profits = sum(Profits, na.rm = T),
    mb = mean(BvBmsy, na.rm = T)
    ,
    mf = mean(FvFmsy, na.rm = T),
    total_biomass = sum(Biomass, na.rm = T)
  ) %>%
  subset(
    Policy %in% c(
      'Business As Usual',
      'Business As Usual Pessimistic'
      ,
      'Catch Share Three',
      'CatchShare',
      'Fmsy',
      'Fmsy Three',
      'Historic'
    )
  )

cheat_fig3$Year[cheat_fig3$Policy == 'Historic' &
                  cheat_fig3$Year == 2012] <- 2050

write.csv(subset(cheat_fig3, Year == max(Year)),
          file =  paste(ResultFolder, 'Figure 3 data.csv', sep = ''))

quick_fig3 <- (
  ggplot(
    subset(cheat_fig3, Year == max(Year)),
    aes(
      total_biomass,
      total_profits,
      size = total_catch,
      fill = Policy
    )
  )
  + geom_point(shape = 21, alpha = 0.6) +
    scale_size_continuous(range  = c(8, 15)) +
    geom_text(aes(label = Policy), size = 3) +
    ylim(c(0, 9e10)) +
    xlim(c(4e8, 15e8)) +
    xlab('Total Biomass') +
    ylab('Total Profits')
)

ggsave(
  paste(FigureFolder, 'Quick Figure 3 Profits 2050.pdf', sep = ''),
  plot = quick_fig3,
  height = 8,
  width = 10
)

trend_check <- ProjectionData %>%
  subset(
    Policy %in% c(
      'Business As Usual',
      'Business As Usual Pessimistic'
      ,
      'Catch Share Three',
      'CatchShare',
      'Fmsy',
      'Fmsy Three',
      'Historic'
    )
  ) %>%
  group_by(Year, Policy) %>%
  summarize(
    total_catch = sum(Catch, na.rm = T),
    total_profits = sum(Profits, na.rm = T),
    total_biomass = sum(Biomass, na.rm = T),
    total_discp = sum(DiscProfits, na.rm = T),
    mean_p = mean(Price, na.rm = T),
    mean_f = mean(FvFmsy, na.rm = T)
  )

oa_check <- ProjectionData %>%
  subset(Dbase == 'FAO' &
           CatchShare == 0 & Policy == 'Business As Usual Pessimistic') %>%
  group_by(Year, Policy) %>%
  summarize(
    total_catch = sum(Catch, na.rm = T),
    total_profits = sum(Profits, na.rm = T),
    total_biomass = sum(Biomass, na.rm = T),
    total_discp = sum(DiscProfits, na.rm = T),
    mean_p = mean(Price, na.rm = T),
    mean_f = mean(FvFmsy, na.rm = T)
  )


trend_plot <-
  ggplot(trend_check, aes(Year, total_catch, fill = Policy, size = mean_f)) + geom_point(shape = 21, alpha = 0.6)

ProjectionData <- ProjectionData %>%
  group_by(IdOrig, Policy) %>%
  mutate(NPV = cumsum(DiscProfits))

ProjectionData$NPV[ProjectionData$Policy == 'Historic'] <- NA

# Calculate fishery upsides on full ProjectionData prior to unlumping stocks

UpsideAllStocks <-
  FisheriesUpsideV3(
    ProjectionData,
    BaselineYear,
    DenominatorPolicy = 'Business As Usual',
    RecoveryThreshold = 0.8,
    LumpedName = 'Lumped Projection Data',
    SubsetName = 'All Stocks',
    IncludeNEIs = IncludeNEIs
  )

UpsideOverfishOnly <-
  FisheriesUpsideV3(
    ProjectionData,
    BaselineYear,
    DenominatorPolicy = 'Business As Usual',
    RecoveryThreshold = 0.8,
    LumpedName = 'Lumped Projection Data',
    SubsetName = 'Overfish Only',
    IncludeNEIs = IncludeNEIs
  )

# Unlump lumped fisheries and create separate ProjectionData dataframe with unlumped stocks

UnlumpedData <-
  DivyUpSofia(ProjectionData, RawData) # Divide up SOFIA multinational

UnlumpedData <-
  DivyMultinational(Data = UnlumpedData, RawData, BaselineYear, YearsBack =
                      4) # Divide up RAM multinational

UnlumpedData <-
  UnlumpFisheries(UnlumpedData,
                  ProjectionData,
                  RawData,
                  BaselineYear,
                  YearsBack = 4,
                  StitchIds) # Divide up lumped FAO fisheries

UnlumpedProjectionData <- UnlumpedData

# UnlumpedProjectionData<-CheckDuplicates(UnlumpedProjectionData[UnlumpedProjectionData$CanProject==T,]) # Final check for duplicated RAM and FAO stocks


UnlumpedProjectionData <-
  UnlumpedProjectionData[!(is.na(UnlumpedProjectionData$IdOrig)), ]

rm(UnlumpedData)

UnlumpedProjectionData <- UnlumpedProjectionData %>%
  group_by(IdOrig, Policy) %>%
  mutate(NPV = cumsum(DiscProfits))

UnlumpedProjectionData$NPV[UnlumpedProjectionData$Policy == 'Historic'] <-
  NA

# write.csv(file=paste(ResultFolder,'Unlumped Projection Data.csv',sep=''),UnlumpedProjectionData)

# Calculate fishery upsides from UnlumpedProjectionData
UnlumpedUpsideAllStocks <-
  FisheriesUpsideV3(
    UnlumpedProjectionData,
    BaselineYear,
    DenominatorPolicy = 'Business As Usual',
    RecoveryThreshold = 0.8,
    LumpedName = 'UnLumped Projection Data',
    SubsetName = 'All Stocks',
    IncludeNEIs = IncludeNEIs
  )


UnlumpedUpsideOverfishOnly <-
  FisheriesUpsideV3(
    UnlumpedProjectionData,
    BaselineYear,
    DenominatorPolicy = 'Business As Usual',
    RecoveryThreshold = 0.8,
    LumpedName = 'UnLumped Projection Data',
    SubsetName = 'Overfish Only',
    IncludeNEIs
  )


### Plot figures for paper and diagnostics  --------------------------------------------------

# FIGURE 3 - Recovery Trajectories

RecoveryTrends <-
  RecoveryTrend(
    ProjectionData = ProjectionData,
    RecoveryThreshold = 0.8,
    OnlyOverfish = FALSE,
    StartYear = 1980
  )

# Global Kobe Plot

MakeKobePlot(ProjectionData, BaselineYear, 'Global Kobe Plot.pdf')

### Diagnostics and Summary Tables -----------------------------------------------------------------------------

## Scenario Results
globalscenarios <-
  ScenarioResults(
    DataU = UnlumpedProjectionData,
    BaselineYear = BaselineYear,
    ResultFolder = ResultFolder,
    Level = 'Global'
  )

countryscenarios <-
  ScenarioResults(
    DataU = UnlumpedProjectionData,
    BaselineYear = BaselineYear,
    ResultFolder = ResultFolder,
    Level = 'Country'
  )

# Projection validation data for Chris
ProjectionValidationData <-
  ProjectionValidation(UnlumpedProjectionData, BaselineYear)

# Produce Country Summary table and Stock List (returns list with Country summaries and Stock list, writes csvs of both)
PercentCoverage <-
  StockAndCountrySummary(UnlumpedProjectionData,
                         ProjectionData,
                         StitchIds,
                         BaselineYear,
                         include_neis = IncludeNEIs)

# Top stocks in major countries
#
# TopStocks <- CountryTopStocks(DataU=UnlumpedProjectionData,DataL=ProjectionData,BaselineYear,Policies=c('Business As Usual','Business As Usual Pessimistic','Catch Share Three','CatchShare','Fmsy Three','Fmsy'),
#                             NumberOfStocks='All',NumberOfCountries='All',Discount,ResultFolder,FileName='Country Results All Stocks')

# Summarize current status by ISSCAAP and FAO Region
StatusByRegionAndISSCAAP <-
  RegionFaoAndISSCAAPSummary(ProjectionData, BaselineYear)

# Upside results by ISSCAAP category
# PlotsForSOM(RawData,FullData,UnlumpedProjectionData,UnlumpedUpsidesAllStocks)

# Cost revenue
CostRevenues <- CostRevCheck(ProjectionData, RawData, BaselineYear)

# Produce figures
CodyPlots(FigureFolder, ResultFolder, Policy = 'Catch Share Three')

CodyPlotsProfit2050(FigureFolder, ResultFolder, Policy = 'Catch Share Three')

# RAM stock list
ramlist <-
  subset(ProjectionData,
         Dbase == 'RAM' & Year == 2012,
         c('CommName', 'Country', 'RegionFAO'))
write.csv(ramlist, file = paste(ResultFolder, 'Ram Stock List.csv', sep =
                                  ''))

# Values for paper
ValuesForPaper <-
  ResultsForPaper(
    DataU = UnlumpedProjectionData,
    DataL = ProjectionData,
    RawData = RawData,
    BaselineYear = BaselineYear,
    ResultFolder = ResultFolder
  )

# write.csv(file=paste(ResultFolder,'Projection Data.csv',sep=''),ProjectionData)

# write.csv(file=paste(ResultFolder,'Unlumped Projection Data.csv',sep=''),UnlumpedProjectionData)
gfr_qaqc(ProjectionData = ProjectionData, FigureFolder = FigureFolder)

save(
  ProjectionData,
  UnlumpedProjectionData,
  OriginalProjectionData,
  file = paste(ResultFolder, 'ProjectionData Data.rdata', sep = '')
)

# save.image(file=paste(ResultFolder,'Global Fishery Recovery Complete Results.rdata',sep=''))
