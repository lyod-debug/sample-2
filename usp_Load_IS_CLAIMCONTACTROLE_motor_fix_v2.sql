USE [IntermediateStaging_DEV]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[usp_Load_IS_CLAIMCONTACTROLE]
AS
BEGIN
    SET NOCOUNT ON;

    /* ========================================================================
       STEP 0: TRUNCATE TARGET & CLEANUP TEMP TABLES
       ======================================================================== */
    TRUNCATE TABLE [IntermediateStaging_DEV].dbo.IS_CLAIMCONTACTROLE;

    IF OBJECT_ID('tempdb..#BASE_CONTACT_ROLE_HH') IS NOT NULL DROP TABLE #BASE_CONTACT_ROLE_HH;
    IF OBJECT_ID('tempdb..#BASE_CONTACT_ROLE_MOTOR') IS NOT NULL DROP TABLE #BASE_CONTACT_ROLE_MOTOR;
    IF OBJECT_ID('tempdb..#HH_EXPOSURE_BY_CASE') IS NOT NULL DROP TABLE #HH_EXPOSURE_BY_CASE;
    IF OBJECT_ID('tempdb..#HH_INCIDENT_BY_CASE') IS NOT NULL DROP TABLE #HH_INCIDENT_BY_CASE;
    IF OBJECT_ID('tempdb..#HH_EXPOSURE_BY_CLAIM') IS NOT NULL DROP TABLE #HH_EXPOSURE_BY_CLAIM;
    IF OBJECT_ID('tempdb..#HH_INCIDENT_BY_CLAIM') IS NOT NULL DROP TABLE #HH_INCIDENT_BY_CLAIM;
    IF OBJECT_ID('tempdb..#MOTOR_EXPOSURE_BY_CASE') IS NOT NULL DROP TABLE #MOTOR_EXPOSURE_BY_CASE;
    IF OBJECT_ID('tempdb..#MOTOR_INCIDENT_BY_CASE') IS NOT NULL DROP TABLE #MOTOR_INCIDENT_BY_CASE;
    IF OBJECT_ID('tempdb..#MOTOR_EXPOSURE_BY_CLAIM') IS NOT NULL DROP TABLE #MOTOR_EXPOSURE_BY_CLAIM;
    IF OBJECT_ID('tempdb..#MOTOR_EXPOSURE_BY_CLAIM_PA') IS NOT NULL DROP TABLE #MOTOR_EXPOSURE_BY_CLAIM_PA;
    IF OBJECT_ID('tempdb..#MOTOR_INCIDENT_BY_CASE_VEH') IS NOT NULL DROP TABLE #MOTOR_INCIDENT_BY_CASE_VEH;
    IF OBJECT_ID('tempdb..#MOTOR_EXPOSURE_BY_CASE_VEH') IS NOT NULL DROP TABLE #MOTOR_EXPOSURE_BY_CASE_VEH;
    IF OBJECT_ID('tempdb..#LKP_ROLES_HH') IS NOT NULL DROP TABLE #LKP_ROLES_HH;
    IF OBJECT_ID('tempdb..#LKP_ROLES_MOTOR') IS NOT NULL DROP TABLE #LKP_ROLES_MOTOR;

    /* ========================================================================
       STEP 1A: HOUSEHOLD BASE CONTACT EXTRACTION r
       ======================================================================== */
    SELECT
        CLM.PublicID AS ClaimPublicID,
        CC.PublicID AS ClaimContactID,
        C.PublicID AS ContactPublicID,
        C.HDR_ID,
        C.GW_HDR_CASEID,
        C.CLAIM_REF,
        C.HDR_TYPE_ID,
        HDR_TYPE.HDR_TYPE,
        C.LINK_TYPE_ID,
        CFLINK_TYPE.LINK_TYPE,
        RSK.COVERABLE_TYPE AS RISKUNIT_COVERABLE_TYPE,
        HDR.CASEID AS V2_SubCaseID,
        'Household' AS PRODUCT
    INTO #BASE_CONTACT_ROLE_HH
    FROM [IntermediateStaging_DEV].dbo.CONTACT_MASTER_HOUSEHOLD C
    INNER JOIN [IntermediateStaging_DEV].dbo.IS_CLAIM_MASTER CLM
        ON C.GW_HDR_CASEID = CLM.GW_HDR_CASEID
       AND CLM.PRODUCT = 'HOUSEHOLD'
    INNER JOIN [IntermediateStaging_DEV].dbo.IS_CLAIMCONTACT CC
        ON CC.ContactID = C.PublicID
       AND CC.ClaimID = CLM.PublicID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GWP_SLCTD_RISK SR
        ON CLM.GW_HDR_CASEID = SR.GW_HDR_CASEID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GWP_RISKUNIT RSK
        ON RSK.GWP_POLICYID = SR.GWP_POLICYID
       AND RSK.PUBLICID = SR.PUBLICID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR
        ON HDR.ID = C.HDR_ID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR_TYPE HDR_TYPE
        ON HDR_TYPE.ID = HDR.GWCONTH_TYPEID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_LINK CF_LINK
        ON CF_LINK.ID = C.LINK_ID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CFLINK_TYPE CFLINK_TYPE
        ON C.LINK_TYPE_ID = CFLINK_TYPE.ID;

    CREATE NONCLUSTERED INDEX IX_BCR ON #BASE_CONTACT_ROLE_HH (HDR_TYPE_ID, LINK_TYPE_ID);
    CREATE NONCLUSTERED INDEX IX_BCR_CASE ON #BASE_CONTACT_ROLE_HH (V2_SubCaseID);

    /* ========================================================================
       STEP 1B: MOTOR BASE CONTACT EXTRACTION
       ======================================================================== */
    SELECT
        CLM.PublicID AS ClaimPublicID,
        CC.PublicID AS ClaimContactID,
        C.PublicID AS ContactPublicID,
        C.HDR_ID,
        C.GW_HDR_CASEID,
        C.CLAIM_REF,
        C.HDR_TYPE_ID,
        HDR_TYPE.HDR_TYPE,
        C.LINK_TYPE_ID,
        CFLINK_TYPE.LINK_TYPE,
        RSK.COVERABLE_TYPE AS RISKUNIT_COVERABLE_TYPE,
        HDR.CASEID AS V2_SubCaseID,
        'Motor' AS PRODUCT
    INTO #BASE_CONTACT_ROLE_MOTOR
    FROM [IntermediateStaging_DEV].dbo.CONTACT_MASTER_MOTOR C
    INNER JOIN [IntermediateStaging_DEV].dbo.IS_CLAIM_MASTER CLM
        ON C.GW_HDR_CASEID = CLM.GW_HDR_CASEID
       AND CLM.PRODUCT = 'MOTOR'
    INNER JOIN [IntermediateStaging_DEV].dbo.IS_CLAIMCONTACT CC
        ON CC.ContactID = C.PublicID
       AND CC.ClaimID = CLM.PublicID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GWP_SLCTD_RISK SR
        ON CLM.GW_HDR_CASEID = SR.GW_HDR_CASEID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GWP_RISKUNIT RSK
        ON RSK.GWP_POLICYID = SR.GWP_POLICYID
       AND RSK.PUBLICID = SR.PUBLICID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR
        ON HDR.ID = C.HDR_ID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR_TYPE HDR_TYPE
        ON HDR_TYPE.ID = HDR.GWCONTH_TYPEID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_LINK CF_LINK
        ON CF_LINK.ID = C.LINK_ID
    LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CFLINK_TYPE CFLINK_TYPE
        ON C.LINK_TYPE_ID = CFLINK_TYPE.ID;

    CREATE NONCLUSTERED INDEX IX_BCRM ON #BASE_CONTACT_ROLE_MOTOR (HDR_TYPE_ID, LINK_TYPE_ID);
    CREATE NONCLUSTERED INDEX IX_BCRM_CASE ON #BASE_CONTACT_ROLE_MOTOR (V2_SubCaseID);

    /* ========================================================================
       STEP 2A: HOUSEHOLD EXPOSURE & INCIDENT PICKERS
       ======================================================================== */
    -- 1. Subcase level (VectusCaseID_Adm: Buildings, Contents, TP)
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.PublicID) AS PickedExposureID
    INTO #HH_EXPOSURE_BY_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_HEBC ON #HH_EXPOSURE_BY_CASE (V2_SubCaseID);

    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.IncidentID) AS PickedIncidentID
    INTO #HH_INCIDENT_BY_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.IncidentID IS NOT NULL
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_HIBC ON #HH_INCIDENT_BY_CASE (V2_SubCaseID);

    -- 2. Main Claim Header level (GW_HDR_CASEID / ClaimPublicID fallback)
    SELECT
        EXP.ClaimID AS ClaimPublicID,
        MIN(EXP.PublicID) AS PickedExposureID
    INTO #HH_EXPOSURE_BY_CLAIM
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    WHERE EXP.LossParty = 'insured'
    GROUP BY EXP.ClaimID;

    CREATE UNIQUE CLUSTERED INDEX CIX_HHEBC ON #HH_EXPOSURE_BY_CLAIM (ClaimPublicID);

    SELECT
        EXP.ClaimID AS ClaimPublicID,
        MIN(EXP.IncidentID) AS PickedIncidentID
    INTO #HH_INCIDENT_BY_CLAIM
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    WHERE EXP.LossParty = 'insured'
      AND EXP.IncidentID IS NOT NULL
    GROUP BY EXP.ClaimID;

    CREATE UNIQUE CLUSTERED INDEX CIX_HHIBC ON #HH_INCIDENT_BY_CLAIM (ClaimPublicID);

    /* ========================================================================
       STEP 2B: MOTOR EXPOSURE & INCIDENT PICKERS
       CHANGED (mapping-driven, see notes): the mapping sheet says which KIND of
       exposure each role links to, so each picker now only looks at that kind:
         - TP roles  ("Link to 1 of the TP exposures created from the V2 TP case")
              -> #MOTOR_EXPOSURE_BY_CASE / #MOTOR_INCIDENT_BY_CASE
                 keyed by TP.ID (VectusCaseID_Adm), TP_* exposures only
         - AD roles  ("ONLY link to the AD/F&T exposure")
              -> #MOTOR_EXPOSURE_BY_CLAIM   (claim header level, AD exposure only)
         - PA roles  ("Link to the 1st party BI exposure created for the V2 PA Anc Case")
              -> #MOTOR_EXPOSURE_BY_CLAIM_PA (claim header level, PA exposure only)
       The old claim-level pickers (any LossParty='insured' exposure / incident)
       are removed: a TP role could fall back to the 1st-party exposure/incident.
       ======================================================================== */
    -- 1. TP subcase level (VectusCaseID_Adm = TP.ID)
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.Exposure_Motor_PublicID) AS PickedExposureID
    INTO #MOTOR_EXPOSURE_BY_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.SourceOrigin_Adm IN ('TP_VEH', 'TP_INJ', 'TP_PRO', 'TP_HIRE')
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_MEBC ON #MOTOR_EXPOSURE_BY_CASE (V2_SubCaseID);

    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.IncidentID) AS PickedIncidentID
    INTO #MOTOR_INCIDENT_BY_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.SourceOrigin_Adm IN ('TP_VEH', 'TP_INJ', 'TP_PRO', 'TP_HIRE')
      AND EXP.IncidentID IS NOT NULL
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_MIBC ON #MOTOR_INCIDENT_BY_CASE (V2_SubCaseID);

    -- 2. 1st party, claim header level: the AD / F&T exposure
    SELECT
        EXP.ClaimID AS ClaimPublicID,
        MIN(EXP.Exposure_Motor_PublicID) AS PickedExposureID
    INTO #MOTOR_EXPOSURE_BY_CLAIM
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.SourceOrigin_Adm = 'AD'
    GROUP BY EXP.ClaimID;

    CREATE UNIQUE CLUSTERED INDEX CIX_MEBCLM ON #MOTOR_EXPOSURE_BY_CLAIM (ClaimPublicID);

    -- 3. 1st party, claim header level: the PA ancillary (BI) exposure
    SELECT
        EXP.ClaimID AS ClaimPublicID,
        MIN(EXP.Exposure_Motor_PublicID) AS PickedExposureID
    INTO #MOTOR_EXPOSURE_BY_CLAIM_PA
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.SourceOrigin_Adm IN ('PA', 'PA_PLUS')
    GROUP BY EXP.ClaimID;

    CREATE UNIQUE CLUSTERED INDEX CIX_MEBCLM_PA ON #MOTOR_EXPOSURE_BY_CLAIM_PA (ClaimPublicID);

    /* ------------------------------------------------------------------------
       LOAD-ERROR DRIVEN (not in the BA mapping sheet - comes from the CCST->CC
       validation queries): these roles may only link to certain incident types.
         repairshop / hirecompany_adm / thirdparty_adm / tpinsurer_Adm -> VehicleIncident only
         recoveryagent -> VehicleIncident only (BA)
       Same TP.ID-level pick as above, but only among incidents of that subtype.
       The subtype comes from IS_EXPOSURE_MOTOR.IncidentType (no IS_INCIDENT join). Run Part 0 of BA_evidence_motor_v3 first.
       ------------------------------------------------------------------------ */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.IncidentID) AS PickedIncidentID
    INTO #MOTOR_INCIDENT_BY_CASE_VEH
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.SourceOrigin_Adm IN ('TP_VEH', 'TP_INJ', 'TP_PRO', 'TP_HIRE')
      AND EXP.IncidentID IS NOT NULL
      AND EXP.IncidentType = 'VehicleDamage'       -- vehicle incident = IncidentType 'VehicleDamage' on IS_EXPOSURE_MOTOR (TP_VEH and TP_HIRE), no IS_INCIDENT
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_MIBC_VEH ON #MOTOR_INCIDENT_BY_CASE_VEH (V2_SubCaseID);

    /* BA: the 5 vehicle-incident roles also link to the CORRESPONDING vehicle exposure = the exposure
       that belongs to the picked VehicleIncident of the same TP case (prefer the TP_VEH exposure,
       else any TP_* exposure on that incident). */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        COALESCE(
            MIN(CASE WHEN EXP.SourceOrigin_Adm = 'TP_VEH' THEN EXP.Exposure_Motor_PublicID END),
            MIN(EXP.Exposure_Motor_PublicID)
        ) AS PickedExposureID
    INTO #MOTOR_EXPOSURE_BY_CASE_VEH
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    INNER JOIN #MOTOR_INCIDENT_BY_CASE_VEH V
        ON V.V2_SubCaseID = EXP.VectusCaseID_Adm
       AND V.PickedIncidentID = EXP.IncidentID
    WHERE EXP.SourceOrigin_Adm IN ('TP_VEH', 'TP_INJ', 'TP_PRO', 'TP_HIRE')
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_MEBC_VEH ON #MOTOR_EXPOSURE_BY_CASE_VEH (V2_SubCaseID);


    /* ========================================================================
       STEP 3A: HOUSEHOLD LOOKUP ROLES POPULATION
       ======================================================================== */
    SELECT
        B.HDR_TYPE_ID,
        B.HDR_TYPE,
        B.LINK_TYPE_ID,
        B.LINK_TYPE,
        B.RISKUNIT_COVERABLE_TYPE,
        LKP.Link_to_Policy,
        B.ClaimPublicID,
        B.ContactPublicID,
        B.HDR_ID,
        B.CLAIM_REF,
        1 AS Active,
        B.ClaimContactID AS ClaimContactID,
        -- Matches specific case folder ID (AD/PA/TP) first; falls back to main claim header exposure
        CASE
            WHEN LKP.Link_to_Exposure = 'YES' THEN COALESCE(EBC.PickedExposureID, EBCLM.PickedExposureID)
            ELSE NULL
        END AS ExposureID,
        -- Matches specific case folder ID (AD/PA/TP) first; falls back to main claim header incident
        CASE
            WHEN LKP.Link_to_Incident = 'YES' THEN COALESCE(IBC.PickedIncidentID, IBCLM.PickedIncidentID)
            ELSE NULL
        END AS IncidentID,
        CASE WHEN LKP.Link_to_Policy = 'YES' THEN B.ClaimPublicID ELSE NULL END AS PolicyID,
        LKP.GWCC_Role_TYPECODE AS Role,
        'Household' AS PRODUCT
    INTO #LKP_ROLES_HH
    FROM #BASE_CONTACT_ROLE_HH B
    LEFT JOIN dbo.CLAIM_CONTACT_ROLE_LOOKUP LKP
        ON LKP.PRODUCT = 'Household'
       AND LKP.HDR_TYPEID = B.HDR_TYPE_ID
       AND LKP.LINK_TYPEID = B.LINK_TYPE_ID
       AND (
            LKP.RISKUNIT_COVERABLE_TYPE = B.RISKUNIT_COVERABLE_TYPE
            OR (
                LKP.RISKUNIT_COVERABLE_TYPE IS NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM dbo.CLAIM_CONTACT_ROLE_LOOKUP X
                    WHERE X.PRODUCT = LKP.PRODUCT
                      AND X.HDR_TYPEID = LKP.HDR_TYPEID
                      AND X.LINK_TYPEID = LKP.LINK_TYPEID
                      AND X.RISKUNIT_COVERABLE_TYPE = B.RISKUNIT_COVERABLE_TYPE
                )
            )
        )
    LEFT JOIN #HH_EXPOSURE_BY_CASE EBC
        ON EBC.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #HH_INCIDENT_BY_CASE IBC
        ON IBC.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #HH_EXPOSURE_BY_CLAIM EBCLM
        ON EBCLM.ClaimPublicID = B.ClaimPublicID
    LEFT JOIN #HH_INCIDENT_BY_CLAIM IBCLM
        ON IBCLM.ClaimPublicID = B.ClaimPublicID;

    CREATE NONCLUSTERED INDEX IX_LKP ON #LKP_ROLES_HH (HDR_TYPE_ID);

    /* ========================================================================
       STEP 3B: MOTOR LOOKUP ROLES POPULATION
       ======================================================================== */
    SELECT
        B.HDR_TYPE_ID,
        B.HDR_TYPE,
        B.LINK_TYPE_ID,
        B.LINK_TYPE,
        B.RISKUNIT_COVERABLE_TYPE,
        LKP.Link_to_Policy,
        B.ClaimPublicID,
        B.ContactPublicID,
        B.HDR_ID,
        B.CLAIM_REF,
        1 AS Active,
        B.ClaimContactID AS ClaimContactID,
        -- ExposureID: which exposure depends on the lookup's EXPOSURE column (mapping-driven)
        CASE
            /* vehicle-incident roles: IF the lookup says Link to Exposure = YES, the exposure is the VEHICLE exposure of the picked vehicle incident. Not YES = no exposure. */
            WHEN LKP.Link_to_Exposure = 'YES'   -- ONLY when the lookup says YES for Link to Exposure; otherwise the exposure stays NULL
                 AND LKP.GWCC_Role_TYPECODE IN ('repairshop', 'hirecompany_adm', 'thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent')
                THEN EBC_VEH.PickedExposureID
            WHEN LKP.Link_to_Exposure = 'YES' THEN
                CASE
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%THIRDPARTY%' THEN EBC.PickedExposureID      -- 1 of the TP exposures of that TP case
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%ANCILLARY%'  THEN EBCLM_PA.PickedExposureID -- the PA (1st party BI) exposure
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%MOTOR AD%'   THEN EBCLM.PickedExposureID    -- the AD / F&T exposure
                    ELSE NULL
                END
            ELSE NULL
        END AS ExposureID,
        -- IncidentID: only TP roles have Link to Incident = YES in the mapping, so TP.ID level only.
        -- LOAD-ERROR DRIVEN: 5 roles restricted to certain incident subtypes (see STEP 2B).
        CASE
            WHEN LKP.Link_to_Incident = 'YES' THEN
                CASE
                    /* BA: these roles HAVE to link to the vehicle incident. recoveryagent included (BA says vehicle). If the case
                       has no VehicleIncident the role is kept with IncidentID NULL and reported to BA. */
                    WHEN LKP.GWCC_Role_TYPECODE IN ('repairshop', 'hirecompany_adm', 'thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent')
                        THEN IBC_VEH.PickedIncidentID
                    ELSE IBC.PickedIncidentID
                END
            ELSE NULL
        END AS IncidentID,
        CASE WHEN LKP.Link_to_Policy = 'YES' THEN B.ClaimPublicID ELSE NULL END AS PolicyID,
        LKP.GWCC_Role_TYPECODE AS Role,
        'Motor' AS PRODUCT
    INTO #LKP_ROLES_MOTOR
    FROM #BASE_CONTACT_ROLE_MOTOR B
    LEFT JOIN dbo.CLAIM_CONTACT_ROLE_LOOKUP LKP
        ON LKP.PRODUCT = 'Motor'
       AND LKP.HDR_TYPEID = B.HDR_TYPE_ID
       AND LKP.LINK_TYPEID = B.LINK_TYPE_ID
       AND (
            LKP.RISKUNIT_COVERABLE_TYPE = B.RISKUNIT_COVERABLE_TYPE
            OR (
                LKP.RISKUNIT_COVERABLE_TYPE IS NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM dbo.CLAIM_CONTACT_ROLE_LOOKUP X
                    WHERE X.PRODUCT = LKP.PRODUCT
                      AND X.HDR_TYPEID = LKP.HDR_TYPEID
                      AND X.LINK_TYPEID = LKP.LINK_TYPEID
                      AND X.RISKUNIT_COVERABLE_TYPE = B.RISKUNIT_COVERABLE_TYPE
                )
            )
        )
    LEFT JOIN #MOTOR_EXPOSURE_BY_CASE EBC
        ON EBC.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_INCIDENT_BY_CASE IBC
        ON IBC.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_EXPOSURE_BY_CASE_VEH EBC_VEH
        ON EBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_INCIDENT_BY_CASE_VEH IBC_VEH
        ON IBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_EXPOSURE_BY_CLAIM EBCLM
        ON EBCLM.ClaimPublicID = B.ClaimPublicID
    LEFT JOIN #MOTOR_EXPOSURE_BY_CLAIM_PA EBCLM_PA
        ON EBCLM_PA.ClaimPublicID = B.ClaimPublicID;

    CREATE NONCLUSTERED INDEX IX_LKPM ON #LKP_ROLES_MOTOR (HDR_TYPE_ID);

    /* ========================================================================
       STEP 4: MANDATORY ROLES (100% UNTOUCHED FROM WORKING VERSION)
       ======================================================================== */
    ;WITH
    /* --- Household Mandatory Insured & Reporter --- */
    MANDATORY_INSURED_ROLE_HH AS (
        SELECT
            B.HDR_TYPE_ID, B.HDR_TYPE, B.LINK_TYPE_ID, B.LINK_TYPE, B.RISKUNIT_COVERABLE_TYPE,
            'YES' AS Link_to_Policy, B.ClaimPublicID, B.ContactPublicID, B.HDR_ID, B.CLAIM_REF,
            1 AS Active, B.ClaimContactID, NULL AS ExposureID, NULL AS IncidentID,
            B.ClaimPublicID AS PolicyID, 'insured' AS Role, 'Household' AS PRODUCT
        FROM #LKP_ROLES_HH B
        WHERE B.HDR_TYPE_ID = 113
    ),
    MANDATORY_REPORTER_ROLE_HH AS (
        SELECT
            B.HDR_TYPE_ID, B.HDR_TYPE, B.LINK_TYPE_ID, B.LINK_TYPE, B.RISKUNIT_COVERABLE_TYPE,
            'NO' AS Link_to_Policy, B.ClaimPublicID, B.ContactPublicID, B.HDR_ID, B.CLAIM_REF,
            1 AS Active, B.ClaimContactID, NULL AS ExposureID, NULL AS IncidentID,
            NULL AS PolicyID, 'reporter' AS Role, 'Household' AS PRODUCT
        FROM #LKP_ROLES_HH B
        WHERE B.HDR_TYPE_ID = 113
    ),

    /* --- Household Mandatory Claimant (Per Exposure) --- */
    MANDATORY_CLAIMANT_ROLE_HH AS (
        /* 1st Party HH Exposures -> Policyholder (HDR 113)*/
        SELECT
            113 AS HDR_TYPE_ID, 'Policy Holder' AS HDR_TYPE, NULL AS LINK_TYPE_ID, NULL AS LINK_TYPE, NULL AS RISKUNIT_COVERABLE_TYPE,
            'NO' AS Link_to_Policy, EXP.ClaimID AS ClaimPublicID, B.ContactPublicID, B.HDR_ID, CLM.CLAIM_REF, 1 AS Active,
            B.ClaimContactID, EXP.PublicID AS ExposureID, NULL AS IncidentID, NULL AS PolicyID,
            'claimant' AS Role, 'Household' AS PRODUCT
        FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
        INNER JOIN IntermediateStaging_DEV.dbo.IS_CLAIM_MASTER CLM
            ON CLM.PublicID = EXP.ClaimID
        INNER JOIN (
            SELECT DISTINCT ClaimPublicID, ClaimContactID, ContactPublicID, HDR_ID
            FROM #BASE_CONTACT_ROLE_HH
            WHERE HDR_TYPE_ID = 113
        ) B ON B.ClaimPublicID = EXP.ClaimID
        WHERE EXP.LossParty = 'insured'

        UNION ALL

        /* 3rd Party HH Exposures -> Third Party Contact (HDR 127)*/
        SELECT
            127 AS HDR_TYPE_ID, 'Third Party' AS HDR_TYPE, NULL AS LINK_TYPE_ID, NULL AS LINK_TYPE, NULL AS RISKUNIT_COVERABLE_TYPE,
            'NO' AS Link_to_Policy, EXP.ClaimID AS ClaimPublicID, TPC.ContactPublicID, TPC.HDR_ID, CLM.CLAIM_REF, 1 AS Active,
            TPC.ClaimContactID, EXP.PublicID AS ExposureID, NULL AS IncidentID, NULL AS PolicyID,
            'claimant' AS Role, 'Household' AS PRODUCT
        FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
        INNER JOIN IntermediateStaging_DEV.dbo.IS_CLAIM_MASTER CLM
            ON CLM.PublicID = EXP.ClaimID
        INNER JOIN (
            SELECT DISTINCT V2_SubCaseID, ClaimContactID, ContactPublicID, HDR_ID
            FROM #BASE_CONTACT_ROLE_HH
            WHERE HDR_TYPE_ID = 127
        ) TPC ON TPC.V2_SubCaseID = CONVERT(VARCHAR(64), EXP.VectusCaseID_Adm)
        WHERE EXP.LossParty = 'third_party'
    ),

    /* --- Motor Mandatory Insured & Reporter --- */
    MANDATORY_INSURED_ROLE_MOTOR AS (
        SELECT
            B.HDR_TYPE_ID, B.HDR_TYPE, B.LINK_TYPE_ID, B.LINK_TYPE, B.RISKUNIT_COVERABLE_TYPE,
            'YES' AS Link_to_Policy, B.ClaimPublicID, B.ContactPublicID, B.HDR_ID, B.CLAIM_REF,
            1 AS Active, B.ClaimContactID, NULL AS ExposureID, NULL AS IncidentID,
            B.ClaimPublicID AS PolicyID, 'insured' AS Role, 'Motor' AS PRODUCT
        FROM #LKP_ROLES_MOTOR B
        WHERE B.HDR_TYPE_ID = 44
    ),
    MANDATORY_REPORTER_ROLE_MOTOR AS (
        SELECT
            B.HDR_TYPE_ID, B.HDR_TYPE, B.LINK_TYPE_ID, B.LINK_TYPE, B.RISKUNIT_COVERABLE_TYPE,
            'NO' AS Link_to_Policy, B.ClaimPublicID, B.ContactPublicID, B.HDR_ID, B.CLAIM_REF,
            1 AS Active, B.ClaimContactID, NULL AS ExposureID, NULL AS IncidentID,
            NULL AS PolicyID, 'reporter' AS Role, 'Motor' AS PRODUCT
        FROM #LKP_ROLES_MOTOR B
        WHERE B.HDR_TYPE_ID = 44
    ),

    /* --- Motor Mandatory Claimant (Per Exposure) --- */
    MANDATORY_CLAIMANT_ROLE_MOTOR AS (
        /* 1st Party Motor Exposures -> Policyholder (HDR 44)*/
        SELECT
            44 AS HDR_TYPE_ID, 'Policy Holder' AS HDR_TYPE, NULL AS LINK_TYPE_ID, NULL AS LINK_TYPE, NULL AS RISKUNIT_COVERABLE_TYPE,
            'NO' AS Link_to_Policy, EXP.ClaimID AS ClaimPublicID, B.ContactPublicID, B.HDR_ID, EXP.CLAIM_REF, 1 AS Active,
            B.ClaimContactID, EXP.Exposure_Motor_PublicID AS ExposureID, NULL AS IncidentID, NULL AS PolicyID,
            'claimant' AS Role, 'Motor' AS PRODUCT
        FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
        INNER JOIN (
            SELECT DISTINCT ClaimPublicID, ClaimContactID, ContactPublicID, HDR_ID
            FROM #BASE_CONTACT_ROLE_MOTOR
            WHERE HDR_TYPE_ID = 44
        ) B ON B.ClaimPublicID = EXP.ClaimID
        WHERE EXP.LossParty = 'insured'

        UNION ALL

        /* 3rd Party Motor Exposures -> Third Party Contact (HDR 55)*/
        SELECT
            55 AS HDR_TYPE_ID, 'Third Party' AS HDR_TYPE, NULL AS LINK_TYPE_ID, NULL AS LINK_TYPE, NULL AS RISKUNIT_COVERABLE_TYPE,
            'NO' AS Link_to_Policy, EXP.ClaimID AS ClaimPublicID, TPC.ContactPublicID, TPC.HDR_ID, EXP.CLAIM_REF, 1 AS Active,
            TPC.ClaimContactID, EXP.Exposure_Motor_PublicID AS ExposureID, NULL AS IncidentID, NULL AS PolicyID,
            'claimant' AS Role, 'Motor' AS PRODUCT
        FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
        INNER JOIN (
            SELECT DISTINCT V2_SubCaseID, ClaimContactID, ContactPublicID, HDR_ID
            FROM #BASE_CONTACT_ROLE_MOTOR
            WHERE HDR_TYPE_ID = 55
        ) TPC ON TPC.V2_SubCaseID = CONVERT(VARCHAR(64), EXP.VectusCaseID_Adm)
        WHERE EXP.LossParty = 'third_party'
    ),

    /* ========================================================================
       COMBINE ALL ROLES
       ======================================================================== */
    FINAL_ROLE AS (
        SELECT * FROM #LKP_ROLES_HH
        UNION ALL
        SELECT * FROM MANDATORY_INSURED_ROLE_HH
        UNION ALL
        SELECT * FROM MANDATORY_REPORTER_ROLE_HH
        UNION ALL
        SELECT * FROM MANDATORY_CLAIMANT_ROLE_HH
        UNION ALL
        SELECT * FROM #LKP_ROLES_MOTOR
        UNION ALL
        SELECT * FROM MANDATORY_INSURED_ROLE_MOTOR
        UNION ALL
        SELECT * FROM MANDATORY_REPORTER_ROLE_MOTOR
        UNION ALL
        SELECT * FROM MANDATORY_CLAIMANT_ROLE_MOTOR
    ),

    /* ========================================================================
       STEP 5: DEDUPLICATION & EXCLUSIONS
       ======================================================================== */
    DEDUP_ROLE AS (
        SELECT
            ROW_NUMBER() OVER (
                PARTITION BY ClaimContactID, Role, ISNULL(PolicyID,''), ISNULL(ExposureID,''), ISNULL(IncidentID,'')
                ORDER BY ClaimContactID
            ) AS RN,
            *
        FROM FINAL_ROLE F
        WHERE Role IS NOT NULL
    )

    /* ========================================================================
       FINAL TARGET INSERT
       ======================================================================== */
    INSERT INTO [IntermediateStaging_DEV].[dbo].[IS_CLAIMCONTACTROLE]
    (
        [PublicID],
        [LUWID],
        [Active],
        [ClaimContactID],
        [ExposureID],
        [IncidentID],
        [PolicyID],
        [Role]
    )
    SELECT
        CAST(
            CASE
                /* 1. Claimant Role */
                WHEN Role = 'claimant' AND PRODUCT = 'Motor'
                    THEN 'mig:motorccr' + CONVERT(VARCHAR(20), HDR_ID) + '_claimant_' + REPLACE(ExposureID, 'mig:motor_', '')
                WHEN Role = 'claimant' AND PRODUCT = 'Household'
                    THEN 'mig:hhccr' + CONVERT(VARCHAR(20), HDR_ID) + '_claimant_' +
                        REPLACE(REPLACE(REPLACE(ExposureID, 'mig:hhb', 'b'), 'mig:hhc', 'c'), 'mig:hhtp', 'tp')
                /* 2. All other Roles */
                WHEN PRODUCT = 'Motor'
                    THEN 'mig:motorccr' + CONVERT(VARCHAR(20), HDR_ID) + '_' + Role
                WHEN PRODUCT = 'Household'
                    THEN 'mig:hhccr' + CONVERT(VARCHAR(20), HDR_ID) + '_' + Role
            END
        AS VARCHAR(64)) AS PublicID,
        CLAIM_REF AS LUWID,
        Active,
        ClaimContactID,
        ExposureID,
        IncidentID,
        PolicyID,
        Role
    FROM DEDUP_ROLE
    WHERE RN = 1;

    /* ========================================================================
       STEP 6: CLEANUP TEMP TABLES
       ======================================================================== */
    DROP TABLE #BASE_CONTACT_ROLE_HH;
    DROP TABLE #BASE_CONTACT_ROLE_MOTOR;
    DROP TABLE #HH_EXPOSURE_BY_CASE;
    DROP TABLE #HH_INCIDENT_BY_CASE;
    DROP TABLE #HH_EXPOSURE_BY_CLAIM;
    DROP TABLE #HH_INCIDENT_BY_CLAIM;
    DROP TABLE #MOTOR_EXPOSURE_BY_CASE;
    DROP TABLE #MOTOR_INCIDENT_BY_CASE;
    DROP TABLE #MOTOR_EXPOSURE_BY_CLAIM;
    DROP TABLE #MOTOR_EXPOSURE_BY_CLAIM_PA;
    DROP TABLE #MOTOR_INCIDENT_BY_CASE_VEH;
    DROP TABLE #MOTOR_EXPOSURE_BY_CASE_VEH;
    DROP TABLE #LKP_ROLES_HH;
    DROP TABLE #LKP_ROLES_MOTOR;

END;
