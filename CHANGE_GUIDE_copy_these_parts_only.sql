/* =====================================================================================
   CHANGE GUIDE - copy ONLY these parts into your proc.  Nothing else in the proc changed.
   Rules used everywhere:
     - Exposure is linked ONLY if the lookup column Link_to_Exposure = 'YES'; otherwise NULL.
     - Incident is linked ONLY if Link_to_Incident = 'YES'; otherwise NULL.
     - NO claim-level fallback (a contact gets the exposure / incident of its OWN case only).
     - 5 Motor roles (repairshop, hirecompany_adm, thirdparty_adm, tpinsurer_Adm, recoveryagent) and
       3 Household roles (thirdparty_adm, tpinsurer_Adm, recoveryagent) take the VEHICLE incident; vehicle exposure only if Link_to_Exposure = 'YES'.
   ===================================================================================== */

/* ---------- 0. TOP OF PROC, with the other DROP TABLE lines: add this one ---------- */
    IF OBJECT_ID('tempdb..#HH_EXPOSURE_BY_CASE_VEH') IS NOT NULL DROP TABLE #HH_EXPOSURE_BY_CASE_VEH;

/* ---------- 0b. STEP 6 CLEANUP, with the other DROP TABLE lines: add this one ---------- */
    DROP TABLE #HH_EXPOSURE_BY_CASE_VEH;

/* =====================================================================================
   HOUSEHOLD
   ===================================================================================== */

/* ---------- H1. STEP 2A (Household pickers): REPLACE your old #HH_INCIDENT_BY_CASE_VEH block (if any) with these two pickers.
                  Put them after the #HH_INCIDENT_BY_CLAIM index line. ---------- */

    /* CHANGE (Household): thirdparty_adm, tpinsurer_Adm, recoveryagent may only sit on a VehicleIncident (Guidewire load errors, same as Motor).
       The household exposure table has no incident type column, so for HOUSEHOLD ONLY we join IS_INCIDENT (filtered to household:
       the exposure side is IS_EXPOSURE_HOUSEHOLD and the incident ID must be a household one 'mig:HH%') to read the subtype.
       NOTHING is deleted: if the TP case has no vehicle incident, these roles keep their row and get NULL incident / NULL exposure
       (BA sees them through the HH checks). */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.IncidentID) AS PickedIncidentID
    INTO #HH_INCIDENT_BY_CASE_VEH
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    INNER JOIN IntermediateStaging_DEV.dbo.IS_INCIDENT INC
        ON INC.PublicID = EXP.IncidentID
       AND INC.PublicID LIKE 'mig:HH%'               -- household incidents only
    WHERE EXP.VectusCaseID_Adm IS NOT NULL
      AND EXP.IncidentID IS NOT NULL
      AND INC.Subtype = 'VehicleIncident'            -- CONFIRM column name Subtype on IS_INCIDENT (run HH check V0 first)
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_HHIBC_VEH ON #HH_INCIDENT_BY_CASE_VEH (V2_SubCaseID);

    /* The vehicle EXPOSURE for the same 3 roles = the household exposure of the same TP case that sits on the picked vehicle incident. */
    SELECT
        EXP.VectusCaseID_Adm AS V2_SubCaseID,
        MIN(EXP.PublicID) AS PickedExposureID
    INTO #HH_EXPOSURE_BY_CASE_VEH
    FROM IntermediateStaging_DEV.dbo.IS_EXPOSURE_HOUSEHOLD EXP
    INNER JOIN #HH_INCIDENT_BY_CASE_VEH V
        ON V.V2_SubCaseID = EXP.VectusCaseID_Adm
       AND V.PickedIncidentID = EXP.IncidentID
    GROUP BY EXP.VectusCaseID_Adm;

    CREATE UNIQUE CLUSTERED INDEX CIX_HEBC_VEH ON #HH_EXPOSURE_BY_CASE_VEH (V2_SubCaseID);


/* ---------- H2. STEP 3A  #LKP_ROLES_HH : REPLACE the two CASE expressions ExposureID and IncidentID
                  (they sit between  B.ClaimContactID AS ClaimContactID,  and  CASE WHEN LKP.Link_to_Policy ... AS PolicyID) ---------- */

        -- Exposure of the contact's OWN case only (no claim-level fallback)
        CASE
            /* CHANGE: ONLY when the lookup says Link to Exposure = YES, these 3 roles link to the VEHICLE exposure of their own TP case
               (no claim-level fallback). If Link to Exposure is not YES the exposure is NULL and only the incident is linked. */
            WHEN LKP.Link_to_Exposure = 'YES' AND LKP.GWCC_Role_TYPECODE IN ('thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent') THEN EBC_VEH.PickedExposureID
            WHEN LKP.GWCC_Role_TYPECODE IN ('thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent') THEN NULL
            WHEN LKP.Link_to_Exposure = 'YES' THEN EBC.PickedExposureID   -- own case only, NO claim-level fallback (not in BA/mapping)
            ELSE NULL
        END AS ExposureID,
        -- incident: see CASE below
        CASE
            WHEN LKP.Link_to_Incident = 'YES' THEN
                CASE
                    /* CC constraint (same load errors as Motor): these 3 roles cannot sit on Injury / FixedProperty / LivingExpenses / Dwelling /
                       OtherStructure / PropertyContents incidents. Only a VehicleIncident is allowed. If the TP case has no vehicle incident the
                       incident stays NULL (role kept on the claim). */
                    WHEN LKP.GWCC_Role_TYPECODE IN ('thirdparty_adm', 'tpinsurer_Adm', 'recoveryagent') THEN IBC_VEH.PickedIncidentID
                    /* other roles with Link to Incident = YES (contractor_adm): the incident of their OWN TP case only - no claim-level fallback */
                    ELSE IBC.PickedIncidentID
                END
            ELSE NULL
        END AS IncidentID,


/* ---------- H3. STEP 3A  #LKP_ROLES_HH : at the END of the FROM / JOIN list, after the last LEFT JOIN (before the ';'), add these joins.
                  (IBC_VEH is new if you did not have it; EBC_VEH is new) ---------- */
    LEFT JOIN #HH_INCIDENT_BY_CASE_VEH IBC_VEH
        ON IBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #HH_EXPOSURE_BY_CASE_VEH EBC_VEH
        ON EBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)

/* =====================================================================================
   MOTOR
   ===================================================================================== */

/* ---------- M1. STEP 2B (Motor pickers): REPLACE your #MOTOR_INCIDENT_BY_CASE_VEH and #MOTOR_EXPOSURE_BY_CASE_VEH blocks with these
                  (vehicle incident comes from IS_EXPOSURE_MOTOR.IncidentType = 'VehicleDamage', no IS_INCIDENT join) ---------- */

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


/* ---------- M2. STEP 3B  #LKP_ROLES_MOTOR : REPLACE the two CASE expressions ExposureID and IncidentID
                  (between  B.ClaimContactID AS ClaimContactID,  and  CASE WHEN LKP.Link_to_Policy ... AS PolicyID) ---------- */

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


/* ---------- M3. STEP 3B  #LKP_ROLES_MOTOR : these two joins must exist at the end of its FROM list (they were already there before) ---------- */
    LEFT JOIN #MOTOR_EXPOSURE_BY_CASE_VEH EBC_VEH
        ON EBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
    LEFT JOIN #MOTOR_INCIDENT_BY_CASE_VEH IBC_VEH
        ON IBC_VEH.V2_SubCaseID = CONVERT(VARCHAR(64), B.V2_SubCaseID)
