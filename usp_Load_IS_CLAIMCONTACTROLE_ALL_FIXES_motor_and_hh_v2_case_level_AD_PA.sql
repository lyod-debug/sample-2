/* =====================================================================================================
   usp_Load_IS_CLAIMCONTACTROLE  -  ONE FILE with ALL changes (Motor + Household)

   RULES USED EVERYWHERE (from the BA transcript, the mapping sheets and the loaded lookup only):
     - ExposureID is filled ONLY when the lookup column Link_to_Exposure = 'YES'. IncidentID ONLY when Link_to_Incident = 'YES'.
     - Third-party roles take the exposure / incident of their OWN TP case. NO claim-level fallback.
     - First-party roles (v2 CHANGE): Motor AD / PA roles take the exposure of THEIR OWN AD / PA case (contact CASEID = case ID, no MIN); Household has no first-party
       exposure link in the lookup (the mandatory claimant is built separately).
     - Nothing is deleted, no row is picked by ROW_NUMBER. A role without a vehicle incident is KEPT with NULL incident / exposure.
     - Mandatory roles logic and PublicID generation are NOT changed.

   WHAT CHANGED (search for these names in the code):
     MOTOR + HOUSEHOLD  STEP 2A / 2B  #HH_INCIDENT_BY_TP_CASE and #MOTOR_INCIDENT_BY_TP_CASE = the incident OF THE PICKED EXPOSURE (no independent MIN)
     MOTOR      STEP 2B   #MOTOR_INCIDENT_BY_TP_CASE_VEH  vehicle incident = IS_EXPOSURE_MOTOR.IncidentType = 'VehicleDamage' (no IS_INCIDENT join)
                STEP 2B   #MOTOR_EXPOSURE_BY_TP_CASE_VEH  vehicle exposure of that incident (prefer TP_VEH)
                STEP 3B   #LKP_ROLES_MOTOR ExposureID / IncidentID CASE  (5 roles: repairshop, hirecompany_adm, thirdparty_adm, tpinsurer_Adm, recoveryagent)
                          Hire-versus-vehicle choice is NOT implemented: it is pending BA (the pick stays the lowest incident ID).
     HOUSEHOLD  STEP 2A   #HH_INCIDENT_BY_TP_CASE_VEH     vehicle incident = IS_INCIDENT.Subtype = 'VehicleIncident' (household incidents, third-party CASE exposures only, selected by the PublicID prefix mig:hhtp)
                STEP 2A   #HH_EXPOSURE_BY_TP_CASE_VEH     vehicle exposure of that incident
                STEP 3A   #LKP_ROLES_HH   ExposureID / IncidentID CASE   (3 roles: thirdparty_adm, tpinsurer_Adm, recoveryagent)
                          claim-level fallback REMOVED for third-party roles
     STEP 0 / STEP 6      DROP lines for the new temp tables
   Household claim-level pickers (#HH_EXPOSURE_BY_CLAIM / #HH_INCIDENT_BY_CLAIM) REMOVED: Household first-party roles have no exposure / incident link in the mapping.
   ===================================================================================================== */
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
    IF OBJECT_ID('tempdb..#HH_EXPOSURE_BY_TP_CASE') IS NOT NULL DROP TABLE #HH_EXPOSURE_BY_TP_CASE;
    IF OBJECT_ID('tempdb..#HH_INCIDENT_BY_TP_CASE') IS NOT NULL DROP TABLE #HH_INCIDENT_BY_TP_CASE;
    IF OBJECT_ID('tempdb..#HH_INCIDENT_BY_TP_CASE_VEH') IS NOT NULL DROP TABLE #HH_INCIDENT_BY_TP_CASE_VEH;
    IF OBJECT_ID('tempdb..#HH_EXPOSURE_BY_TP_CASE_VEH') IS NOT NULL DROP TABLE #HH_EXPOSURE_BY_TP_CASE_VEH;
    IF OBJECT_ID('tempdb..#MOTOR_EXPOSURE_BY_TP_CASE') IS NOT NULL DROP TABLE #MOTOR_EXPOSURE_BY_TP_CASE;
    IF OBJECT_ID('tempdb..#MOTOR_INCIDENT_BY_TP_CASE') IS NOT NULL DROP TABLE #MOTOR_INCIDENT_BY_TP_CASE;
    IF OBJECT_ID('tempdb..#MOTOR_EXPOSURE_BY_AD_CASE') IS NOT NULL DROP TABLE #MOTOR_EXPOSURE_BY_AD_CASE;
    IF OBJECT_ID('tempdb..#MOTOR_EXPOSURE_BY_PA_CASE') IS NOT NULL DROP TABLE #MOTOR_EXPOSURE_BY_PA_CASE;
    IF OBJECT_ID('tempdb..#MOTOR_INCIDENT_BY_TP_CASE_VEH') IS NOT NULL DROP TABLE #MOTOR_INCIDENT_BY_TP_CASE_VEH;
    IF OBJECT_ID('tempdb..#MOTOR_EXPOSURE_BY_TP_CASE_VEH') IS NOT NULL DROP TABLE #MOTOR_EXPOSURE_BY_TP_CASE_VEH;
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
    -- Third-party case level (VectusCaseID_Adm of the mig:hhtp exposures)
    /* v2 CHANGE: NO MIN. A household TP case (VEC_HH_THIRDPARTY.ID) is NOT split into several exposures: it has ONE exposure PublicID ('mig:hhtp' + HHT.ID),
       so there is nothing to pick: plain SELECT, no MIN, no DISTINCT.
       The unique index below is the CHECK: if the exposure table repeats the same case (same PublicID twice, e.g. the damage_id / incident-detail duplicates), the proc stops with a duplicate-key error. Fix the exposure table, do not hide it here. */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        EXP.PublicID AS PickedExposureID
    INTO #HH_EXPOSURE_BY_TP_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.PublicID LIKE 'mig:hhtp%';   -- third-party CASE exposures only: the PublicID prefix is hard-coded per block of the exposure proc (mig:hhtp = TP, mig:hhb = buildings, mig:hhc = contents); case IDs come from 3 tables and can repeat

    CREATE UNIQUE CLUSTERED INDEX CIX_HEBC ON #HH_EXPOSURE_BY_TP_CASE (V2_SubCaseID);

    /* CHANGE: the incident is the incident OF THE EXPOSURE THAT WAS PICKED above, not an independent MIN over all incidents of the case.
       NOTE: while the household exposure table has one PublicID on several rows with different incidents (the damage_id duplicates), the incident of
       "the picked exposure" is still ambiguous for those cases (lowest incident of that PublicID). It becomes exact once the exposure PublicIDs are unique. */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.IncidentID) AS PickedIncidentID
    INTO #HH_INCIDENT_BY_TP_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    INNER JOIN #HH_EXPOSURE_BY_TP_CASE PX
        ON PX.V2_SubCaseID = EXP.VectusCaseID_Adm
       AND PX.PickedExposureID = EXP.PublicID
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.PublicID LIKE 'mig:hhtp%'   -- third-party case exposures only (same reason as above)
      AND EXP.IncidentID IS NOT NULL
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_HIBC ON #HH_INCIDENT_BY_TP_CASE (V2_SubCaseID);

    /* CHANGE (Household): thirdparty_adm, tpinsurer_Adm, recoveryagent may only sit on a VehicleIncident (Guidewire load errors, same as Motor).
       The household exposure table has no incident type column, so for HOUSEHOLD ONLY we join IS_INCIDENT (filtered to household:
       the exposure side is IS_EXPOSURE_HOUSEHOLD and the incident ID must be a household one 'mig:HH%') to read the subtype.
       NOTHING is deleted: if the TP case has no vehicle incident, these roles keep their row and get NULL incident / NULL exposure
       (BA sees them through the HH checks). */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.IncidentID) AS PickedIncidentID
    INTO #HH_INCIDENT_BY_TP_CASE_VEH
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    INNER JOIN IntermediateStaging_DEV.dbo.IS_INCIDENT INC
        ON INC.PublicID = EXP.IncidentID
       AND INC.PublicID LIKE 'mig:HH%'               -- household incidents only
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.PublicID LIKE 'mig:hhtp%'   -- third-party CASE exposures only. Buildings / contents exposures can ALSO carry a vehicle incident ('mig:HH_veh<id>', no _tp), but they are not the TP case's incident
      AND EXP.IncidentID IS NOT NULL
      AND INC.Subtype = 'VehicleIncident'            -- CONFIRM column name Subtype on IS_INCIDENT (run HH check V0 first)
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_HHIBC_VEH ON #HH_INCIDENT_BY_TP_CASE_VEH (V2_SubCaseID);

    /* The vehicle EXPOSURE for the same 3 roles = the household exposure of the same TP case that sits on the picked vehicle incident. */
    SELECT   -- v2 CHANGE: no MIN, no DISTINCT: one TP case = one exposure PublicID
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        EXP.PublicID AS PickedExposureID
    INTO #HH_EXPOSURE_BY_TP_CASE_VEH
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    INNER JOIN #HH_INCIDENT_BY_TP_CASE_VEH V
        ON V.V2_SubCaseID = EXP.VectusCaseID_Adm
       AND V.PickedIncidentID = EXP.IncidentID
    WHERE EXP.PublicID LIKE 'mig:hhtp%';   -- third-party CASE exposures only

    CREATE UNIQUE CLUSTERED INDEX CIX_HEBC_VEH ON #HH_EXPOSURE_BY_TP_CASE_VEH (V2_SubCaseID);

    /* ========================================================================
       STEP 2B: MOTOR EXPOSURE & INCIDENT PICKERS
       CHANGED (mapping-driven, see notes): the mapping sheet says which KIND of
       exposure each role links to, so each picker now only looks at that kind:
         - TP roles  ("Link to 1 of the TP exposures created from the V2 TP case")
              -> #MOTOR_EXPOSURE_BY_TP_CASE / #MOTOR_INCIDENT_BY_TP_CASE
                 keyed by TP.ID (VectusCaseID_Adm), TP_* exposures only
         - AD roles  ("ONLY link to the AD/F&T exposure")
              -> #MOTOR_EXPOSURE_BY_AD_CASE  (AD CASE level: contact CASEID = AD case ID, AD exposure only)
         - PA roles  ("Link to the 1st party BI exposure created for the V2 PA Anc Case")
              -> #MOTOR_EXPOSURE_BY_PA_CASE  (PA CASE level: contact CASEID = PA case ID, PA exposure only)
       The old claim-level pickers (any LossParty='insured' exposure / incident)
       are removed: a TP role could fall back to the 1st-party exposure/incident.
       ======================================================================== */
    -- 1. TP subcase level (VectusCaseID_Adm = TP.ID)
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.Exposure_Motor_PublicID) AS PickedExposureID
    INTO #MOTOR_EXPOSURE_BY_TP_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.SourceOrigin_Adm IN ('TP_VEH', 'TP_INJ', 'TP_PRO', 'TP_HIRE')
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_MEBC ON #MOTOR_EXPOSURE_BY_TP_CASE (V2_SubCaseID);

    /* CHANGE: the incident is the incident OF THE EXPOSURE THAT WAS PICKED above (same exposure row), not an independent MIN over all incidents.
       Reason: exposure IDs and incident IDs sort differently (e.g. exposure 'mig:motor_tp_hm..' sorts first, but incident 'mig:motor_fpi_tp..' / 'mig:motor_inj_tp..'
       sort before 'mig:motor_veh_HM..'), so two independent MINs can point to two different exposures of the same TP case. */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.IncidentID) AS PickedIncidentID      -- one exposure has one IncidentID; MIN only collapses identical rows
    INTO #MOTOR_INCIDENT_BY_TP_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    INNER JOIN #MOTOR_EXPOSURE_BY_TP_CASE PX
        ON PX.V2_SubCaseID = EXP.VectusCaseID_Adm
       AND PX.PickedExposureID = EXP.Exposure_Motor_PublicID
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.SourceOrigin_Adm IN ('TP_VEH', 'TP_INJ', 'TP_PRO', 'TP_HIRE')
      AND EXP.IncidentID IS NOT NULL
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_MIBC ON #MOTOR_INCIDENT_BY_TP_CASE (V2_SubCaseID);

    -- 2. 1st party AD case level (CHANGED): each AD case (VectusCaseID_Adm = VEC_GW_MOTOR_AD.ID) has exactly ONE AD exposure (AD is not split by element),
    --    so there is NOTHING to pick: no MIN, no DISTINCT. The contact is matched to ITS OWN AD case: contact header CASEID = AD case ID (BA example, claim 139970616).
    --    The unique index below is the CHECK: if an AD case has the same exposure twice, the proc stops on purpose (fix the exposure table, PublicID must be unique).
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        EXP.Exposure_Motor_PublicID AS PickedExposureID
    INTO #MOTOR_EXPOSURE_BY_AD_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.SourceOrigin_Adm = 'AD';

    CREATE UNIQUE CLUSTERED INDEX CIX_MEBAD ON #MOTOR_EXPOSURE_BY_AD_CASE (V2_SubCaseID);

    -- 3. 1st party PA case level (CHANGED): each PA case (VectusCaseID_Adm = VEC_PA_ANCILLARY.ID) has ONE PA exposure; no MIN. Matched by contact header CASEID = PA case ID.
    --    The exposure proc stores 'PA' for both PA and PA_PLUS (PA_PLUS is only the lookup RuleKey).
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        EXP.Exposure_Motor_PublicID AS PickedExposureID
    INTO #MOTOR_EXPOSURE_BY_PA_CASE
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.SourceOrigin_Adm = 'PA';

    CREATE UNIQUE CLUSTERED INDEX CIX_MEBPA ON #MOTOR_EXPOSURE_BY_PA_CASE (V2_SubCaseID);

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
    INTO #MOTOR_INCIDENT_BY_TP_CASE_VEH
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.SourceOrigin_Adm IN ('TP_VEH', 'TP_INJ', 'TP_PRO', 'TP_HIRE')
      AND EXP.IncidentID IS NOT NULL
      AND EXP.IncidentType = 'VehicleDamage'       -- vehicle incident = IncidentType 'VehicleDamage' on IS_EXPOSURE_MOTOR (TP_VEH and TP_HIRE), no IS_INCIDENT
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_MIBC_VEH ON #MOTOR_INCIDENT_BY_TP_CASE_VEH (V2_SubCaseID);

    /* BA: the 5 vehicle-incident roles also link to the CORRESPONDING vehicle exposure = the exposure
       that belongs to the picked VehicleIncident of the same TP case (prefer the TP_VEH exposure,
       else any TP_* exposure on that incident). */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        COALESCE(
            MIN(CASE WHEN EXP.SourceOrigin_Adm = 'TP_VEH' THEN EXP.Exposure_Motor_PublicID END),
            MIN(EXP.Exposure_Motor_PublicID)
        ) AS PickedExposureID
    INTO #MOTOR_EXPOSURE_BY_TP_CASE_VEH
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_MOTOR EXP
    INNER JOIN #MOTOR_INCIDENT_BY_TP_CASE_VEH V
        ON V.V2_SubCaseID = EXP.VectusCaseID_Adm
       AND V.PickedIncidentID = EXP.IncidentID
    WHERE EXP.SourceOrigin_Adm IN ('TP_VEH', 'TP_INJ', 'TP_PRO', 'TP_HIRE')
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_MEBC_VEH ON #MOTOR_EXPOSURE_BY_TP_CASE_VEH (V2_SubCaseID);


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
        -- ExposureID: ONLY when the lookup says Link to Exposure = YES. The lookup's EXPOSURE text says which exposure. (same pattern as IncidentID below)
        CASE
            WHEN LKP.Link_to_Exposure = 'YES' THEN
                CASE
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%THIRDPARTY%' THEN
                        CASE
                            WHEN LKP.GWCC_Role_TYPECODE IN ('thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent')
                                THEN EBC_VEH.PickedExposureID   -- vehicle roles: the VEHICLE exposure of their own TP case
                            ELSE EBC.PickedExposureID   -- other TP roles: the exposure of their OWN TP case. No claim-level fallback.
                        END
                    /* first-party Household: the lookup has no first-party row with Link to Exposure = YES (claimant is built separately).
                       If the mapping sheet gets one, add its branch here. */
                    ELSE NULL
                END
            ELSE NULL
        END AS ExposureID,
        -- IncidentID: ONLY when the lookup says Link to Incident = YES. Same pattern as ExposureID above.
        CASE
            WHEN LKP.Link_to_Incident = 'YES' THEN
                CASE
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%THIRDPARTY%' THEN
                        CASE
                            WHEN LKP.GWCC_Role_TYPECODE IN ('thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent')
                                THEN IBC_VEH.PickedIncidentID   -- vehicle roles: the VEHICLE incident of their own TP case (Guidewire accepts only VehicleIncident). None = NULL, role kept.
                            ELSE IBC.PickedIncidentID   -- other TP roles: the incident of their OWN TP case. No claim-level fallback.
                        END
                    ELSE NULL   -- incidents exist only for TP cases; first-party roles have Link to Incident = NO in the lookup
                END
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
    LEFT JOIN #HH_EXPOSURE_BY_TP_CASE EBC
        ON EBC.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #HH_INCIDENT_BY_TP_CASE IBC
        ON IBC.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #HH_INCIDENT_BY_TP_CASE_VEH IBC_VEH
        ON IBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #HH_EXPOSURE_BY_TP_CASE_VEH EBC_VEH
        ON EBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID);

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
        -- ExposureID: ONLY when the lookup says Link to Exposure = YES. The lookup's EXPOSURE text says which exposure. (same pattern as IncidentID below)
        CASE
            WHEN LKP.Link_to_Exposure = 'YES' THEN
                CASE
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%THIRDPARTY%' THEN
                        CASE
                            WHEN LKP.GWCC_Role_TYPECODE IN ('repairshop', 'hirecompany_adm', 'thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent')
                                THEN EBC_VEH.PickedExposureID   -- vehicle roles: the VEHICLE exposure of their own TP case
                            ELSE EBC.PickedExposureID   -- other TP roles: the exposure of their OWN TP case. No claim-level fallback.
                        END
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%ANCILLARY%'    THEN EBPA.PickedExposureID   -- first party: the PA exposure of the contact's OWN PA case (CASEID = PA case ID)
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%MOTOR AD%'     THEN EBAD.PickedExposureID      -- first party: the AD exposure of the contact's OWN AD case (CASEID = AD case ID)
                    ELSE NULL
                END
            ELSE NULL
        END AS ExposureID,
        -- IncidentID: ONLY when the lookup says Link to Incident = YES. Same pattern as ExposureID above.
        CASE
            WHEN LKP.Link_to_Incident = 'YES' THEN
                CASE
                    WHEN UPPER(LKP.EXPOSURE) LIKE '%THIRDPARTY%' THEN
                        CASE
                            WHEN LKP.GWCC_Role_TYPECODE IN ('repairshop', 'hirecompany_adm', 'thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent')
                                THEN IBC_VEH.PickedIncidentID   -- vehicle roles: the VEHICLE incident of their own TP case (Guidewire accepts only VehicleIncident). None = NULL, role kept.
                            ELSE IBC.PickedIncidentID   -- other TP roles: the incident of their OWN TP case. No claim-level fallback.
                        END
                    ELSE NULL   -- incidents exist only for TP cases; first-party roles have Link to Incident = NO in the lookup
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
    LEFT JOIN #MOTOR_EXPOSURE_BY_TP_CASE EBC
        ON EBC.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_INCIDENT_BY_TP_CASE IBC
        ON IBC.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_EXPOSURE_BY_TP_CASE_VEH EBC_VEH
        ON EBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_INCIDENT_BY_TP_CASE_VEH IBC_VEH
        ON IBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_EXPOSURE_BY_AD_CASE EBAD
        ON EBAD.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_EXPOSURE_BY_PA_CASE EBPA
        ON EBPA.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID);

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
          AND EXP.PublicID LIKE 'mig:hhtp%'   -- same prefix filter as the pickers: Household case IDs come from 3 tables and can repeat
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
    DROP TABLE #HH_EXPOSURE_BY_TP_CASE;
    DROP TABLE #HH_INCIDENT_BY_TP_CASE;
    DROP TABLE #HH_INCIDENT_BY_TP_CASE_VEH;
    DROP TABLE #HH_EXPOSURE_BY_TP_CASE_VEH;
    DROP TABLE #MOTOR_EXPOSURE_BY_TP_CASE;
    DROP TABLE #MOTOR_INCIDENT_BY_TP_CASE;
    DROP TABLE #MOTOR_EXPOSURE_BY_AD_CASE;
    DROP TABLE #MOTOR_EXPOSURE_BY_PA_CASE;
    DROP TABLE #MOTOR_INCIDENT_BY_TP_CASE_VEH;
    DROP TABLE #MOTOR_EXPOSURE_BY_TP_CASE_VEH;
    DROP TABLE #LKP_ROLES_HH;
    DROP TABLE #LKP_ROLES_MOTOR;

END;
