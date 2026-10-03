/* =====================================================================================
   BA EVIDENCE v3 - MOTOR - CLAIM CONTACT ROLES
   - Reads only IS_EXPOSURE_MOTOR, IS_CLAIMCONTACTROLE, IS_CLAIMCONTACT, IS_CLAIM_MASTER, CONTACT_MASTER_MOTOR, lookup.
   - NO dependency on IS_INCIDENT for the BA lists. The incident type comes from IS_EXPOSURE_MOTOR.IncidentType.
     (IS_INCIDENT is used ONLY in the two INTERNAL checks, marked "INTERNAL", never send those to BA.)
   - Each problem case shows ONLY its own exposures and their own incidents.
   - Nothing in usp_Load_IS_CLAIMCONTACTROLE is changed by this file. Nothing is deleted anywhere.

   PART 0  Check IncidentType is filled in IS_EXPOSURE_MOTOR           (run first)
   PART 1  Roles that must link to a vehicle incident, the case has none (per claim / case / role)
   PART 2  Different claim contacts, same role, same exposure (or incident)
   PART 3  Hire checks (4 checks)
   PART 4  INTERNAL: why a TP case has no exposure; exposure incident IDs missing from IS_INCIDENT
   PART 5  How to hold the incident subtype in IS_EXPOSURE_MOTOR (already exists: IncidentType)
   PART 6  FIRST PARTY (AD) and PA ANCILLARY cases - linked by the claim header case ID
   PART 7  Proof that the proc output matches the rule (TP vehicle roles) - run after the proc

   ASSUMED NAMES (verify): IS_EXPOSURE_MOTOR.(Exposure_Motor_PublicID, ClaimID, VectusCaseID_Adm, SourceOrigin_Adm,
   IncidentID, IncidentType), IS_CLAIM_MASTER.(PublicID, CLAIM_REF, GW_HDR_CASEID, PRODUCT),
   IS_CLAIMCONTACT.(PublicID, ContactID, ClaimID), IS_CLAIMCONTACTROLE.(PublicID, ClaimContactID, Role, ExposureID, IncidentID)
   ===================================================================================== */
USE IntermediateStaging_DEV;
GO

/* ============================ PART 0 - IS IncidentType FILLED? ============================ */
-- 0a. what IncidentType really holds. Seen in the data: TP_VEH and TP_HIRE = 'VehicleDamage', TP_INJ = 'BodilyInjuryDamage'.
--     Check the value for TP_PRO and AD / PA here. 'VehicleDamage' is what these queries (and the proc) treat as the vehicle incident.
SELECT SourceOrigin_Adm, IncidentType,
       COUNT(*) AS Exposures,
       SUM(CASE WHEN IncidentID IS NULL THEN 1 ELSE 0 END) AS ExposuresWithoutIncidentID
FROM dbo.IS_EXPOSURE_MOTOR
GROUP BY SourceOrigin_Adm, IncidentType
ORDER BY SourceOrigin_Adm, IncidentType;

-- 0b. exposures that HAVE an IncidentID but NO IncidentType (must be 0 rows, otherwise the BA lists below are not reliable)
SELECT SourceOrigin_Adm, COUNT(*) AS ExposuresWithIncidentIDButNoType
FROM dbo.IS_EXPOSURE_MOTOR
WHERE IncidentID IS NOT NULL AND (IncidentType IS NULL OR LTRIM(RTRIM(IncidentType)) = '')
GROUP BY SourceOrigin_Adm;


/* ============================ SETUP (PARTS 1 and 3) ============================ */
IF OBJECT_ID('tempdb..#T_EXP')  IS NOT NULL DROP TABLE #T_EXP;
IF OBJECT_ID('tempdb..#T_CASE') IS NOT NULL DROP TABLE #T_CASE;
IF OBJECT_ID('tempdb..#T_BASE') IS NOT NULL DROP TABLE #T_BASE;
IF OBJECT_ID('tempdb..#T_PROB') IS NOT NULL DROP TABLE #T_PROB;

/* every TP exposure with its own incident (all from IS_EXPOSURE_MOTOR) */
SELECT CONVERT(VARCHAR(64), E.VectusCaseID_Adm) AS CaseID,
       E.Exposure_Motor_PublicID                AS ExposureID,
       E.SourceOrigin_Adm                       AS Origin,
       E.IncidentID, E.IncidentType
INTO #T_EXP
FROM dbo.IS_EXPOSURE_MOTOR E
WHERE E.SourceOrigin_Adm IN ('TP_VEH','TP_INJ','TP_PRO','TP_HIRE');
CREATE CLUSTERED INDEX IX_T_EXP ON #T_EXP (CaseID);

/* one row per TP case: counts + the case's own exposures / incidents as text */
SELECT X.CaseID,
       COUNT(*)                                                                            AS Exposures,
       SUM(CASE WHEN X.IncidentID IS NOT NULL THEN 1 ELSE 0 END)                           AS ExposuresWithIncidentID,
       SUM(CASE WHEN X.IncidentID IS NOT NULL AND X.IncidentType = 'VehicleDamage' THEN 1 ELSE 0 END) AS ExposuresOnVehicleIncident,
       STRING_AGG(CONVERT(VARCHAR(MAX),
            X.ExposureID + ' [' + X.Origin + ']  -> incident: ' +
            ISNULL(X.IncidentID, '(NO IncidentID on this exposure)') +
            CASE WHEN X.IncidentID IS NOT NULL THEN ' (' + ISNULL(X.IncidentType, 'type empty on exposure') + ')' ELSE '' END),
            '  ||  ')                                                                       AS OwnExposuresAndIncidents
INTO #T_CASE
FROM #T_EXP X
GROUP BY X.CaseID;
CREATE UNIQUE CLUSTERED INDEX IX_T_CASE ON #T_CASE (CaseID);

/* contacts whose role must link to an incident (lookup Link_to_Incident = YES) */
SELECT DISTINCT
       CLM.CLAIM_REF AS ClaimRef, CLM.PublicID AS ClaimPublicID, C.GW_HDR_CASEID AS GW_HDR_CASEID,
       CONVERT(VARCHAR(64), HDR.CASEID) AS TP_CaseID,
       C.HDR_ID, C.HDR_TYPE_ID, C.LINK_TYPE_ID,
       L.GWCC_Role_TYPECODE AS Role,
       CASE WHEN L.GWCC_Role_TYPECODE IN ('repairshop','hirecompany_adm','thirdparty_adm','tpinsurer_Adm','recoveryagent')
            THEN 1 ELSE 0 END AS NeedsVehicleIncident
INTO #T_BASE
FROM dbo.CONTACT_MASTER_MOTOR C
JOIN dbo.IS_CLAIM_MASTER CLM ON C.GW_HDR_CASEID = CLM.GW_HDR_CASEID AND CLM.PRODUCT = 'MOTOR'
JOIN dbo.IS_CLAIMCONTACT CC  ON CC.ContactID = C.PublicID AND CC.ClaimID = CLM.PublicID
LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = C.HDR_ID
JOIN dbo.CLAIM_CONTACT_ROLE_LOOKUP L
       ON L.PRODUCT = 'Motor' AND L.HDR_TYPEID = C.HDR_TYPE_ID AND L.LINK_TYPEID = C.LINK_TYPE_ID
WHERE L.Link_to_Incident = 'YES' AND L.GWCC_Role_TYPECODE IN ('repairshop','hirecompany_adm','thirdparty_adm','tpinsurer_Adm','recoveryagent');
CREATE NONCLUSTERED INDEX IX_T_BASE ON #T_BASE (TP_CaseID);

/* problem rows. Only TP-side contacts (their CASEID is a TP.ID). Reasons use only the case's OWN exposures. */
SELECT B.*, C.Exposures, C.ExposuresWithIncidentID, C.ExposuresOnVehicleIncident, C.OwnExposuresAndIncidents,
       CASE WHEN C.CaseID IS NULL                  THEN 'P1 - this TP case has NO exposure (so no incident either)'
            WHEN C.ExposuresWithIncidentID = 0     THEN 'P2 - this TP case has exposure(s) but none has an IncidentID'
            ELSE                                        'P3 - this TP case has incident(s) but none is a vehicle incident (IncidentType VehicleDamage)'
       END AS Problem
INTO #T_PROB
FROM #T_BASE B
LEFT JOIN #T_CASE C ON C.CaseID = B.TP_CaseID
WHERE B.TP_CaseID IN (SELECT CONVERT(VARCHAR(64), ID) FROM SourceStaging.VECCASRN.VEC_GW_MOTOR_TP)   -- TP-side contacts only
  AND (C.CaseID IS NULL OR C.ExposuresWithIncidentID = 0 OR C.ExposuresOnVehicleIncident = 0);
/* ============================ END SETUP ============================ */


/* ============================ PART 1 - NO VEHICLE INCIDENT ON THE CASE ============================ */
-- 1a. SUMMARY (show first)
SELECT Role, Problem, COUNT(*) AS ContactRoleRows, COUNT(DISTINCT ClaimRef) AS Claims, COUNT(DISTINCT TP_CaseID) AS TP_Cases
FROM #T_PROB
GROUP BY Role, Problem
ORDER BY Problem, ContactRoleRows DESC;

-- 1b. LIST FOR BA: one row per claim / TP case / role, with the case's OWN exposures and incidents
DECLARE @Role    VARCHAR(60) = NULL;   -- one role at a time, or NULL for all
DECLARE @Problem VARCHAR(2)  = 'P3';   -- 'P1' no exposure, 'P2' exposure without IncidentID, 'P3' only non-vehicle incidents
SELECT P.ClaimRef, P.GW_HDR_CASEID, P.TP_CaseID AS TP_ID_CaseID, P.Role,
       COUNT(*) AS Contacts,
       STRING_AGG(CONVERT(VARCHAR(20), P.HDR_ID), ', ') AS HDR_IDs,
       MIN(P.Problem) AS Problem,
       ISNULL(MIN(P.OwnExposuresAndIncidents), '(no exposure on this case)') AS ExposuresAndIncidentsOfThisCase
FROM #T_PROB P
WHERE LEFT(P.Problem, 2) = @Problem AND (@Role IS NULL OR P.Role = @Role)
GROUP BY P.ClaimRef, P.GW_HDR_CASEID, P.TP_CaseID, P.Role
ORDER BY P.Role, P.ClaimRef;

-- 1c. ONE CASE IN DETAIL (one row per exposure of that case, nothing from other cases)
DECLARE @CaseID VARCHAR(64) = '222241290';     -- put a TP.ID here
SELECT @CaseID AS TP_ID_CaseID, X.ExposureID, X.Origin AS ExposureType,
       ISNULL(X.IncidentID, '(NO IncidentID on this exposure)') AS IncidentID,
       ISNULL(X.IncidentType, CASE WHEN X.IncidentID IS NULL THEN '-' ELSE 'type empty on exposure' END) AS IncidentType
FROM #T_EXP X WHERE X.CaseID = @CaseID
UNION ALL
SELECT @CaseID, '(this case has no exposure rows in IS_EXPOSURE_MOTOR)', NULL, NULL, NULL
WHERE NOT EXISTS (SELECT 1 FROM #T_EXP WHERE CaseID = @CaseID);


/* ============================ PART 2 - SAME ROLE, SAME EXPOSURE, DIFFERENT CLAIM CONTACTS ============================
   Counts CLAIM CONTACTS (IS_CLAIMCONTACTROLE.ClaimContactID). Whether they are the same real person is NOT checked.   */
IF OBJECT_ID('tempdb..#D_GRP') IS NOT NULL DROP TABLE #D_GRP;
IF OBJECT_ID('tempdb..#D_DET') IS NOT NULL DROP TABLE #D_DET;

SELECT R.ExposureID, R.Role
INTO #D_GRP
FROM dbo.IS_CLAIMCONTACTROLE R
WHERE R.PublicID LIKE 'mig:motorccr%' AND R.ExposureID IS NOT NULL
GROUP BY R.ExposureID, R.Role
HAVING COUNT(DISTINCT R.ClaimContactID) > 1;
CREATE CLUSTERED INDEX IX_D_GRP ON #D_GRP (ExposureID, Role);

SELECT DISTINCT G.ExposureID, G.Role, R.ClaimContactID, CC.ClaimID,
       TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 13, NULLIF(CHARINDEX('_', R.PublicID, 13), 0) - 13)) AS HDR_ID
INTO #D_DET
FROM #D_GRP G
JOIN dbo.IS_CLAIMCONTACTROLE R ON R.ExposureID = G.ExposureID AND R.Role = G.Role AND R.PublicID LIKE 'mig:motorccr%'
JOIN dbo.IS_CLAIMCONTACT CC    ON CC.PublicID = R.ClaimContactID;

-- 2a. SUMMARY by role (~450K groups overall, so show this first)
SELECT Role, COUNT(*) AS ExposureRoleGroups, COUNT(DISTINCT ExposureID) AS Exposures
FROM #D_GRP GROUP BY Role ORDER BY ExposureRoleGroups DESC;

-- 2b. LIST FOR BA: one row per exposure / role.  Filter with @DupRole (strongly recommended: one role at a time)
DECLARE @DupRole VARCHAR(60) = 'hirecompany_adm';
SELECT CLM.CLAIM_REF       AS ClaimRef,
       CLM.GW_HDR_CASEID   AS GW_HDR_CASEID,
       E.SourceOrigin_Adm  AS ExposureType,
       E.VectusCaseID_Adm  AS CaseID,                 -- TP.ID for TP exposures; header case ID for AD / PA
       X.ExposureID, E.IncidentID,
       X.Role,
       X.ClaimContacts     AS NumberOfClaimContacts,
       X.ClaimContactIDs,
       X.HDR_IDs
FROM (SELECT D.ExposureID, D.Role, MIN(D.ClaimID) AS ClaimID,
             COUNT(DISTINCT D.ClaimContactID) AS ClaimContacts,
             STRING_AGG(CONVERT(VARCHAR(100), D.ClaimContactID), ', ') AS ClaimContactIDs,
             STRING_AGG(CONVERT(VARCHAR(20),  D.HDR_ID), ', ')         AS HDR_IDs
      FROM #D_DET D WHERE D.Role = @DupRole GROUP BY D.ExposureID, D.Role) X
JOIN dbo.IS_CLAIM_MASTER CLM      ON CLM.PublicID = X.ClaimID
LEFT JOIN dbo.IS_EXPOSURE_MOTOR E ON E.Exposure_Motor_PublicID = X.ExposureID
ORDER BY CLM.CLAIM_REF;

-- 2c. same role, same INCIDENT, different claim contacts (load errors #8 / #9 = recoveryagent, tpinsurer_Adm)
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID, X.IncidentID, X.IncidentType, X.Role,
       X.ClaimContacts AS NumberOfClaimContacts, X.ClaimContactIDs
FROM (SELECT R.IncidentID, R.Role, MIN(CC.ClaimID) AS ClaimID,
             MIN(EI.IncidentType) AS IncidentType,
             COUNT(DISTINCT R.ClaimContactID) AS ClaimContacts,
             STRING_AGG(CONVERT(VARCHAR(100), R.ClaimContactID), ', ') AS ClaimContactIDs
      FROM (SELECT DISTINCT IncidentID, Role, ClaimContactID FROM dbo.IS_CLAIMCONTACTROLE
            WHERE PublicID LIKE 'mig:motorccr%' AND IncidentID IS NOT NULL
              AND Role IN ('recoveryagent','tpinsurer_Adm')) R          -- change / remove this role filter to check others
      JOIN dbo.IS_CLAIMCONTACT CC ON CC.PublicID = R.ClaimContactID
      LEFT JOIN (SELECT IncidentID, MIN(IncidentType) AS IncidentType FROM dbo.IS_EXPOSURE_MOTOR WHERE IncidentID IS NOT NULL GROUP BY IncidentID) EI
             ON EI.IncidentID = R.IncidentID
      GROUP BY R.IncidentID, R.Role
      HAVING COUNT(DISTINCT R.ClaimContactID) > 1) X
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.PublicID = X.ClaimID
ORDER BY X.Role, CLM.CLAIM_REF;


/* ============================ PART 3 - HIRE CHECKS (no proc change, BA decides) ============================
   Hire exposure = IS_EXPOSURE_MOTOR.SourceOrigin_Adm = 'TP_HIRE'. Hire incident = the IncidentID of a TP_HIRE exposure
   (data shows mig:motor_veh_HM...). Vehicle (non-hire) incident = IncidentID of a TP_VEH exposure.
   WHICH ROLES ARE 'HIRE COMPANY ROLES' IS A BA DECISION. Edit the list below.                                     */
IF OBJECT_ID('tempdb..#HIRE_ROLES') IS NOT NULL DROP TABLE #HIRE_ROLES;
CREATE TABLE #HIRE_ROLES (Role VARCHAR(60) PRIMARY KEY);
INSERT INTO #HIRE_ROLES VALUES ('hirecompany_adm');      -- add 'credithirecompany_adm', 'hireancillary_adm' only if BA says so

IF OBJECT_ID('tempdb..#HIRE_EXP') IS NOT NULL DROP TABLE #HIRE_EXP;
SELECT DISTINCT CaseID, ExposureID, IncidentID INTO #HIRE_EXP FROM #T_EXP WHERE Origin = 'TP_HIRE';
CREATE CLUSTERED INDEX IX_HIRE_EXP ON #HIRE_EXP (CaseID);

IF OBJECT_ID('tempdb..#VEH_EXP') IS NOT NULL DROP TABLE #VEH_EXP;
SELECT DISTINCT CaseID, ExposureID, IncidentID INTO #VEH_EXP FROM #T_EXP WHERE Origin = 'TP_VEH';

/* all role rows that point at a hire exposure or a hire incident */
IF OBJECT_ID('tempdb..#R_HIRE') IS NOT NULL DROP TABLE #R_HIRE;
SELECT R.PublicID, R.ClaimContactID, R.Role, R.ExposureID, R.IncidentID,
       TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 13, NULLIF(CHARINDEX('_', R.PublicID, 13), 0) - 13)) AS HDR_ID
INTO #R_HIRE
FROM dbo.IS_CLAIMCONTACTROLE R
WHERE R.PublicID LIKE 'mig:motorccr%' AND R.ExposureID IN (SELECT ExposureID FROM #HIRE_EXP)
UNION
SELECT R.PublicID, R.ClaimContactID, R.Role, R.ExposureID, R.IncidentID,
       TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 13, NULLIF(CHARINDEX('_', R.PublicID, 13), 0) - 13))
FROM dbo.IS_CLAIMCONTACTROLE R
WHERE R.PublicID LIKE 'mig:motorccr%' AND R.IncidentID IN (SELECT IncidentID FROM #HIRE_EXP WHERE IncidentID IS NOT NULL);

-- H1. roles that are NOT hire company roles but are linked to a hire exposure / hire incident
-- summary
SELECT H.Role, COUNT(*) AS RoleRows,
       SUM(CASE WHEN H.ExposureID IN (SELECT ExposureID FROM #HIRE_EXP) THEN 1 ELSE 0 END) AS LinkedToHireExposure,
       SUM(CASE WHEN H.IncidentID IN (SELECT IncidentID FROM #HIRE_EXP WHERE IncidentID IS NOT NULL) THEN 1 ELSE 0 END) AS LinkedToHireIncident
FROM #R_HIRE H WHERE H.Role NOT IN (SELECT Role FROM #HIRE_ROLES)
GROUP BY H.Role ORDER BY RoleRows DESC;
-- list (filter one role at a time)
DECLARE @H1Role VARCHAR(60) = NULL;
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID, CONVERT(VARCHAR(64), HDR.CASEID) AS TP_ID_CaseID,
       H.Role, H.ClaimContactID, H.HDR_ID, H.ExposureID AS LinkedExposure, H.IncidentID AS LinkedIncident
FROM #R_HIRE H
JOIN dbo.IS_CLAIMCONTACT CC ON CC.PublicID = H.ClaimContactID
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.PublicID = CC.ClaimID
LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = H.HDR_ID
WHERE H.Role NOT IN (SELECT Role FROM #HIRE_ROLES) AND (@H1Role IS NULL OR H.Role = @H1Role)
ORDER BY H.Role, CLM.CLAIM_REF;

-- H2. hire company role whose case HAS a hire exposure, but the role is linked to something that is not the hire exposure / hire incident
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID, CONVERT(VARCHAR(64), HDR.CASEID) AS TP_ID_CaseID,
       R.Role, R.ClaimContactID, HR.HDR_ID,
       ISNULL(R.ExposureID, '(none)') AS LinkedExposure, ISNULL(R.IncidentID, '(none)') AS LinkedIncident,
       (SELECT STRING_AGG(h.ExposureID + ' / ' + ISNULL(h.IncidentID,'(no IncidentID)'), ', ') FROM #HIRE_EXP h WHERE h.CaseID = CONVERT(VARCHAR(64), HDR.CASEID)) AS HireExposureAndIncidentOnCase
FROM dbo.IS_CLAIMCONTACTROLE R
CROSS APPLY (SELECT TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 13, NULLIF(CHARINDEX('_', R.PublicID, 13), 0) - 13)) AS HDR_ID) HR
JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = HR.HDR_ID
JOIN dbo.IS_CLAIMCONTACT CC ON CC.PublicID = R.ClaimContactID
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.PublicID = CC.ClaimID
WHERE R.PublicID LIKE 'mig:motorccr%'
  AND R.Role IN (SELECT Role FROM #HIRE_ROLES)
  AND EXISTS (SELECT 1 FROM #HIRE_EXP h WHERE h.CaseID = CONVERT(VARCHAR(64), HDR.CASEID))
  AND NOT EXISTS (SELECT 1 FROM #HIRE_EXP h WHERE h.CaseID = CONVERT(VARCHAR(64), HDR.CASEID)
                  AND (h.ExposureID = R.ExposureID OR h.IncidentID = R.IncidentID))
ORDER BY CLM.CLAIM_REF;

-- H3. TP case has a hire exposure / incident but NO contact with a hire company role
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID, H.CaseID AS TP_ID_CaseID,
       H.ExposureID AS HireExposure, ISNULL(H.IncidentID, '(NO IncidentID on this exposure)') AS HireIncident
FROM #HIRE_EXP H
JOIN dbo.IS_EXPOSURE_MOTOR E ON E.Exposure_Motor_PublicID = H.ExposureID
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.PublicID = E.ClaimID
WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.CONTACT_MASTER_MOTOR C
        JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = C.HDR_ID
        JOIN dbo.CLAIM_CONTACT_ROLE_LOOKUP L ON L.PRODUCT = 'Motor' AND L.HDR_TYPEID = C.HDR_TYPE_ID AND L.LINK_TYPEID = C.LINK_TYPE_ID
        WHERE CONVERT(VARCHAR(64), HDR.CASEID) = H.CaseID
          AND L.GWCC_Role_TYPECODE IN (SELECT Role FROM #HIRE_ROLES))
ORDER BY CLM.CLAIM_REF;

-- H4. TP case has a hire company contact but NO hire exposure / incident
SELECT CLM.CLAIM_REF AS ClaimRef, C.GW_HDR_CASEID AS GW_HDR_CASEID, CONVERT(VARCHAR(64), HDR.CASEID) AS TP_ID_CaseID,
       L.GWCC_Role_TYPECODE AS Role, C.HDR_ID, C.PublicID AS ContactID
FROM dbo.CONTACT_MASTER_MOTOR C
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.GW_HDR_CASEID = C.GW_HDR_CASEID AND CLM.PRODUCT = 'MOTOR'
JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = C.HDR_ID
JOIN SourceStaging.VECCASRN.VEC_GW_MOTOR_TP TPC ON TPC.ID = HDR.CASEID            -- TP-side contact
JOIN dbo.CLAIM_CONTACT_ROLE_LOOKUP L ON L.PRODUCT = 'Motor' AND L.HDR_TYPEID = C.HDR_TYPE_ID AND L.LINK_TYPEID = C.LINK_TYPE_ID
WHERE L.GWCC_Role_TYPECODE IN (SELECT Role FROM #HIRE_ROLES)
  AND NOT EXISTS (SELECT 1 FROM #HIRE_EXP H WHERE H.CaseID = CONVERT(VARCHAR(64), HDR.CASEID))
ORDER BY CLM.CLAIM_REF;

-- H5. (extra, same idea) the 4 NON-hire vehicle roles linked ONLY to a hire incident while the same case has a normal vehicle incident
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID, CONVERT(VARCHAR(64), HDR.CASEID) AS TP_ID_CaseID,
       R.Role, R.ClaimContactID, R.IncidentID AS LinkedIncident,
       (SELECT STRING_AGG(v.IncidentID, ', ') FROM #VEH_EXP v WHERE v.CaseID = CONVERT(VARCHAR(64), HDR.CASEID)) AS NormalVehicleIncidentOnCase
FROM dbo.IS_CLAIMCONTACTROLE R
CROSS APPLY (SELECT TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 13, NULLIF(CHARINDEX('_', R.PublicID, 13), 0) - 13)) AS HDR_ID) HR
JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = HR.HDR_ID
JOIN dbo.IS_CLAIMCONTACT CC ON CC.PublicID = R.ClaimContactID
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.PublicID = CC.ClaimID
WHERE R.PublicID LIKE 'mig:motorccr%'
  AND R.Role IN ('repairshop','thirdparty_adm','tpinsurer_Adm','recoveryagent')
  AND EXISTS (SELECT 1 FROM #HIRE_EXP h WHERE h.IncidentID = R.IncidentID)
  AND EXISTS (SELECT 1 FROM #VEH_EXP v WHERE v.CaseID = CONVERT(VARCHAR(64), HDR.CASEID))
ORDER BY R.Role, CLM.CLAIM_REF;


/* ============================ PART 4 - INTERNAL (NOT FOR BA) ============================ */
-- 4a. TP cases with NO exposure (P1): which source join of the exposure proc loses them?
--     The exposure proc builds TP exposures from:  IS_CLAIM_MASTER (product MOTOR, claim <> 1112416534)
--       INNER JOIN VEC_GW_MOTOR_TP (TP.GW_HDR_CASEID = CLM.GW_HDR_CASEID)
--       INNER JOIN VEC_GW_TP_SUMMARY (TPS.CASEID = TP.ID)
--       INNER JOIN VEC_GW_TPTYPE (TPTYPE.ID = TPS.GW_TP_TYPEID)
--       then INNER JOIN LKP_EXPOSURE_MOTOR_RULES, INNER JOIN VEC_CASE (VC.ID = TP.ID), INNER JOIN VEC_GW_CASE_STATUS (CS.CASEID = TP.ID AND GCURRENT = 'X')
--     (confirm against your latest proc). Each row below tells which first join fails.
SELECT Z.WhereItIsLost, COUNT(*) AS TP_Cases
FROM (SELECT DISTINCT P.TP_CaseID,
        CASE WHEN TP.ID  IS NULL THEN '1 TP.ID not in VEC_GW_MOTOR_TP'
             WHEN CLM.PublicID IS NULL THEN '2 TP.GW_HDR_CASEID has no MOTOR claim in IS_CLAIM_MASTER (or claim excluded in proc)'
             WHEN TPS.ID IS NULL THEN '3 no row in VEC_GW_TP_SUMMARY  (INNER JOIN in the proc drops it)'
             WHEN TT.ID  IS NULL THEN '4 TP_SUMMARY.GW_TP_TYPEID has no row in VEC_GW_TPTYPE  (INNER JOIN in the proc drops it)'
             WHEN VC.ID  IS NULL THEN '5 no row in VEC_CASE  (INNER JOIN in the proc drops it)'
             WHEN CS.CASEID IS NULL THEN '6 no VEC_GW_CASE_STATUS row with GCURRENT = X  (INNER JOIN in the proc drops it)'
             ELSE '7 passes all joins - lost for another reason (hire-only path, rules table, or filter)' END AS WhereItIsLost
      FROM #T_PROB P
      LEFT JOIN SourceStaging.VECCASRN.VEC_GW_MOTOR_TP   TP  ON TP.ID = TRY_CONVERT(BIGINT, P.TP_CaseID)
      LEFT JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.GW_HDR_CASEID = TP.GW_HDR_CASEID AND UPPER(LTRIM(RTRIM(CLM.PRODUCT))) = 'MOTOR'
      LEFT JOIN SourceStaging.VECCASRN.VEC_GW_TP_SUMMARY TPS ON TPS.CASEID = TP.ID
      LEFT JOIN SourceStaging.VECCASRN.VEC_GW_TPTYPE     TT  ON TT.ID = TPS.GW_TP_TYPEID
      LEFT JOIN SourceStaging.VECCASRN.VEC_CASE          VC  ON VC.ID = TP.ID
      LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CASE_STATUS CS ON CS.CASEID = TP.ID AND CS.GCURRENT = 'X'
      WHERE P.Problem LIKE 'P1%') Z
GROUP BY Z.WhereItIsLost ORDER BY TP_Cases DESC;

-- 4b. INTERNAL (the only IS_INCIDENT use): exposures whose IncidentID is NOT in IS_INCIDENT - per exposure type.
--     Not for BA: this is the incident-table gap for your colleague.
SELECT E.SourceOrigin_Adm AS ExposureType, COUNT(*) AS ExposuresWithIncidentID,
       SUM(CASE WHEN I.PublicID IS NULL THEN 1 ELSE 0 END) AS 'IncidentID on exposure NOT FOUND in IS_INCIDENT'
FROM dbo.IS_EXPOSURE_MOTOR E
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = E.IncidentID
WHERE E.IncidentID IS NOT NULL
GROUP BY E.SourceOrigin_Adm ORDER BY 3 DESC;

-- 4c. INTERNAL: one case - its own exposures and whether each incident exists in IS_INCIDENT (explicit text, no 'unknown')
DECLARE @CaseID2 VARCHAR(64) = '222241290';
SELECT X.CaseID, X.ExposureID, X.Origin, X.IncidentID, X.IncidentType,
       CASE WHEN X.IncidentID IS NULL THEN 'exposure has no IncidentID'
            WHEN I.PublicID IS NULL   THEN 'IncidentID on exposure is NOT FOUND in IS_INCIDENT'
            ELSE 'IncidentID found in IS_INCIDENT' END AS IncidentTableCheck
FROM #T_EXP X LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = X.IncidentID
WHERE X.CaseID = @CaseID2;


/* ============================ PART 5 - INCIDENT SUBTYPE IN IS_EXPOSURE_MOTOR ============================
   IS_EXPOSURE_MOTOR ALREADY HAS IncidentType. The exposure proc fills it (INSERT ... /* IncidentType */ R.IncidentType_Code)
   from LKP_EXPOSURE_MOTOR_RULES: TP_VEH + TP_HIRE = VehicleDamage, TP_INJ = BodilyInjuryDamage (as seen in the data; check TP_PRO in Part 0a).
   So NO new column is needed IF Part 0 shows those values and 0b returns no rows.
   Hire vs normal vehicle incident is told apart with SourceOrigin_Adm ('TP_HIRE' vs 'TP_VEH'), because both are VehicleDamage.

   Only if Part 0 shows NULLs, check the rules table first:                                                         */
SELECT RuleKey, V2CaseFlow, IncidentType_Code FROM dbo.LKP_EXPOSURE_MOTOR_RULES WHERE V2CaseFlow = 'GW MOTOR TP' ORDER BY RuleKey;

/* If a rules row has NULL IncidentType_Code, fix the RULES TABLE (one UPDATE there), then re-run the exposure proc.
   Do not patch IS_EXPOSURE_MOTOR by hand.   Example (confirm the codes with BA first):
   (the codes are the ones Part 0a shows, i.e. VehicleDamage / BodilyInjuryDamage; confirm the rest with BA)

   If you still want a SEPARATE column (only if you decide so), this is all it takes:
   ALTER TABLE dbo.IS_EXPOSURE_MOTOR ADD IncidentSubtype_Adm VARCHAR(50) NULL;
   -- in the exposure proc, in each INSERT column list add  IncidentSubtype_Adm  and in the SELECT add  R.IncidentType_Code AS IncidentSubtype_Adm
   -- (same expression as the existing IncidentType column, so it would just duplicate it)

   LATER, when you decide to change the claim contact role proc (NOT now): replace its #MOTOR_INCIDENT_BY_CASE_VEH build, which
   joins IS_INCIDENT on Subtype = 'VehicleIncident', with a filter on  EXP.IncidentType = 'VehicleDamage'  taken from the
   IS_EXPOSURE_MOTOR rows it already reads. That removes the IS_INCIDENT dependency.                                     */


/* =====================================================================================
   PART 6 - FIRST PARTY (AD) AND PA ANCILLARY
   Link: the contact's GW_HDR_CASEID = the claim's GW_HDR_CASEID (= the AD / PA case header). There is no TP.ID.
   What the proc does for these (usp_Load_IS_CLAIMCONTACTROLE_motor_fix_v2, STEP 3B):
     lookup EXPOSURE text contains 'MOTOR AD'   -> ExposureID = MIN(exposure) of the claim's AD exposures
     lookup EXPOSURE text contains 'ANCILLARY'  -> ExposureID = MIN(exposure) of the claim's PA / PA_PLUS exposures
     Incident: only roles with Link_to_Incident = YES get an incident, and F4 below shows whether any first-party role has that.
   BA rule: if more than one exposure is created, linking to any one of them is enough. These queries show where the claim
   has NONE (role kept, exposure blank) or MORE THAN ONE (the proc takes the lowest ID, nobody decided that).
   ===================================================================================== */
IF OBJECT_ID('tempdb..#FP_EXP')   IS NOT NULL DROP TABLE #FP_EXP;
IF OBJECT_ID('tempdb..#FP_CLAIM') IS NOT NULL DROP TABLE #FP_CLAIM;
IF OBJECT_ID('tempdb..#FP_BASE')  IS NOT NULL DROP TABLE #FP_BASE;

SELECT E.ClaimID, E.Exposure_Motor_PublicID AS ExposureID, E.SourceOrigin_Adm AS Origin,
       CASE WHEN E.SourceOrigin_Adm = 'AD' THEN 'AD' ELSE 'PA' END AS Kind
INTO #FP_EXP
FROM dbo.IS_EXPOSURE_MOTOR E
WHERE E.SourceOrigin_Adm IN ('AD','PA','PA_PLUS');
CREATE CLUSTERED INDEX IX_FP_EXP ON #FP_EXP (ClaimID, Kind);

SELECT ClaimID, Kind, COUNT(*) AS Exposures, MIN(ExposureID) AS ProcPicks,
       STRING_AGG(ExposureID + ' [' + Origin + ']', '  ||  ') AS ExposuresOnClaim
INTO #FP_CLAIM
FROM #FP_EXP GROUP BY ClaimID, Kind;
CREATE UNIQUE CLUSTERED INDEX IX_FP_CLAIM ON #FP_CLAIM (ClaimID, Kind);

/* contacts whose lookup row says "link to the AD exposure" or "link to the PA ancillary exposure" (same precedence as the proc) */
SELECT DISTINCT CLM.CLAIM_REF AS ClaimRef, CLM.PublicID AS ClaimPublicID, C.GW_HDR_CASEID, C.HDR_ID, C.PublicID AS ContactID,
       L.GWCC_Role_TYPECODE AS Role,
       CASE WHEN UPPER(L.EXPOSURE) LIKE '%ANCILLARY%' THEN 'PA' ELSE 'AD' END AS Kind
INTO #FP_BASE
FROM dbo.CONTACT_MASTER_MOTOR C
JOIN dbo.IS_CLAIM_MASTER CLM ON C.GW_HDR_CASEID = CLM.GW_HDR_CASEID AND CLM.PRODUCT = 'MOTOR'
JOIN dbo.IS_CLAIMCONTACT CC  ON CC.ContactID = C.PublicID AND CC.ClaimID = CLM.PublicID
JOIN dbo.CLAIM_CONTACT_ROLE_LOOKUP L ON L.PRODUCT = 'Motor' AND L.HDR_TYPEID = C.HDR_TYPE_ID AND L.LINK_TYPEID = C.LINK_TYPE_ID
WHERE L.Link_to_Exposure = 'YES'
  AND UPPER(L.EXPOSURE) NOT LIKE '%THIRDPARTY%'
  AND (UPPER(L.EXPOSURE) LIKE '%ANCILLARY%' OR UPPER(L.EXPOSURE) LIKE '%MOTOR AD%')
  AND NOT (L.Link_to_Incident = 'YES' AND L.GWCC_Role_TYPECODE IN ('repairshop','hirecompany_adm','thirdparty_adm','tpinsurer_Adm','recoveryagent'));
CREATE NONCLUSTERED INDEX IX_FP_BASE ON #FP_BASE (ClaimPublicID, Kind);

-- F1. roles that must link to the AD / PA exposure but the claim HAS NONE of that kind  (role is kept, ExposureID blank)
-- summary
SELECT B.Kind, B.Role, COUNT(*) AS ContactRoleRows, COUNT(DISTINCT B.ClaimRef) AS Claims
FROM #FP_BASE B LEFT JOIN #FP_CLAIM F ON F.ClaimID = B.ClaimPublicID AND F.Kind = B.Kind
WHERE F.ClaimID IS NULL
GROUP BY B.Kind, B.Role ORDER BY B.Kind, ContactRoleRows DESC;
-- list for BA (filter one kind / role at a time)
DECLARE @FPKind VARCHAR(2) = 'AD';          -- 'AD' or 'PA'
DECLARE @FPRole VARCHAR(60) = NULL;
SELECT B.ClaimRef, B.GW_HDR_CASEID, B.Kind AS ExposureKindNeeded, B.Role,
       COUNT(*) AS Contacts, STRING_AGG(CONVERT(VARCHAR(20), B.HDR_ID), ', ') AS HDR_IDs,
       'claim has no ' + B.Kind + ' exposure' AS Problem,
       ISNULL((SELECT STRING_AGG(X.ExposureID + ' [' + X.Origin + ']', '  ||  ') FROM #FP_EXP X WHERE X.ClaimID = B.ClaimPublicID),
              '(claim has no first-party exposure at all)') AS FirstPartyExposuresOfThisClaim
FROM #FP_BASE B LEFT JOIN #FP_CLAIM F ON F.ClaimID = B.ClaimPublicID AND F.Kind = B.Kind
WHERE F.ClaimID IS NULL AND B.Kind = @FPKind AND (@FPRole IS NULL OR B.Role = @FPRole)
GROUP BY B.ClaimRef, B.GW_HDR_CASEID, B.Kind, B.Role, B.ClaimPublicID
ORDER BY B.Role, B.ClaimRef;

-- F2. the claim has MORE THAN ONE exposure of the kind: the proc links to the lowest exposure ID. Nobody decided that. For BA.
SELECT B.Kind, COUNT(DISTINCT B.ClaimPublicID) AS ClaimsWithMoreThanOneExposure
FROM #FP_BASE B JOIN #FP_CLAIM F ON F.ClaimID = B.ClaimPublicID AND F.Kind = B.Kind AND F.Exposures > 1
GROUP BY B.Kind;
SELECT B.ClaimRef, B.GW_HDR_CASEID, B.Kind, F.Exposures AS NumberOfExposures, F.ExposuresOnClaim, F.ProcPicks AS ExposureTheProcLinksTo,
       COUNT(*) AS ContactRoleRowsAffected, STRING_AGG(B.Role, ', ') AS Roles
FROM (SELECT DISTINCT ClaimRef, ClaimPublicID, GW_HDR_CASEID, Kind, Role FROM #FP_BASE) B
JOIN #FP_CLAIM F ON F.ClaimID = B.ClaimPublicID AND F.Kind = B.Kind AND F.Exposures > 1
WHERE B.Kind = @FPKind
GROUP BY B.ClaimRef, B.GW_HDR_CASEID, B.Kind, F.Exposures, F.ExposuresOnClaim, F.ProcPicks
ORDER BY B.ClaimRef;

-- F3. proof against the loaded table: first-party / PA roles whose ExposureID is blank although the claim has that kind,
--     or whose ExposureID is of another kind (both counts should be 0)
SELECT B.Kind, B.Role, COUNT(*) AS LoadedRows,
       SUM(CASE WHEN R.ExposureID IS NULL AND F.ClaimID IS NOT NULL THEN 1 ELSE 0 END) AS BlankButClaimHasExposure,
       SUM(CASE WHEN R.ExposureID IS NOT NULL AND ISNULL(E.SourceOrigin_Adm,'?') NOT IN (CASE WHEN B.Kind='AD' THEN 'AD' ELSE 'PA' END, CASE WHEN B.Kind='AD' THEN 'AD' ELSE 'PA_PLUS' END) THEN 1 ELSE 0 END) AS LinkedToOtherKind
FROM dbo.IS_CLAIMCONTACTROLE R
CROSS APPLY (SELECT TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 13, NULLIF(CHARINDEX('_', R.PublicID, 13), 0) - 13)) AS HDR_ID) H
JOIN #FP_BASE B ON B.HDR_ID = H.HDR_ID AND B.Role = R.Role
LEFT JOIN #FP_CLAIM F ON F.ClaimID = B.ClaimPublicID AND F.Kind = B.Kind
LEFT JOIN dbo.IS_EXPOSURE_MOTOR E ON E.Exposure_Motor_PublicID = R.ExposureID
WHERE R.PublicID LIKE 'mig:motorccr%'
GROUP BY B.Kind, B.Role ORDER BY B.Kind, B.Role;

-- F4. does ANY first-party / PA lookup role have Link_to_Incident = YES?  (if rows appear, first-party incidents need checks too)
SELECT L.EXPOSURE, L.GWCC_Role_TYPECODE AS Role, L.Link_to_Incident, L.Link_to_Exposure
FROM dbo.CLAIM_CONTACT_ROLE_LOOKUP L
WHERE L.PRODUCT = 'Motor' AND L.Link_to_Incident = 'YES' AND UPPER(ISNULL(L.EXPOSURE,'')) NOT LIKE '%THIRDPARTY%'
ORDER BY L.EXPOSURE, L.GWCC_Role_TYPECODE;

-- F5. same role, same exposure, different claim contacts - first party / PA only (needs Part 2 setup: #D_GRP)
SELECT E.SourceOrigin_Adm AS ExposureType, G.Role, COUNT(*) AS ExposureRoleGroups
FROM #D_GRP G JOIN dbo.IS_EXPOSURE_MOTOR E ON E.Exposure_Motor_PublicID = G.ExposureID
WHERE E.SourceOrigin_Adm IN ('AD','PA','PA_PLUS')
GROUP BY E.SourceOrigin_Adm, G.Role ORDER BY ExposureRoleGroups DESC;
-- list: use query 2b with @DupRole set to a role from F5 (it already prints ClaimRef, GW_HDR_CASEID, ExposureType, CaseID = header case ID for AD / PA)


/* =====================================================================================
   PART 7 - PROOF THAT THE PROC MATCHES THE RULE (TP vehicle roles). All counts must be 0. Run after the proc.
   ===================================================================================== */
-- V1. role must link to a vehicle incident, the case has one, but the role loaded with no incident
-- V2. role loaded with an incident that is NOT a vehicle incident of its own case
SELECT R.Role,
       SUM(CASE WHEN C.ExposuresOnVehicleIncident > 0 AND R.IncidentID IS NULL THEN 1 ELSE 0 END) AS V1_CaseHasVehicleIncidentButRoleHasNone,
       SUM(CASE WHEN R.IncidentID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM #T_EXP X WHERE X.CaseID = CONVERT(VARCHAR(64), HDR.CASEID)
                                                               AND X.IncidentID = R.IncidentID AND X.IncidentType = 'VehicleDamage')
                THEN 1 ELSE 0 END) AS V2_RoleLinkedToNonVehicleIncident
FROM dbo.IS_CLAIMCONTACTROLE R
CROSS APPLY (SELECT TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 13, NULLIF(CHARINDEX('_', R.PublicID, 13), 0) - 13)) AS HDR_ID) H
JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = H.HDR_ID
JOIN #T_CASE C ON C.CaseID = CONVERT(VARCHAR(64), HDR.CASEID)
WHERE R.PublicID LIKE 'mig:motorccr%'
  AND R.Role IN ('repairshop','hirecompany_adm','thirdparty_adm','tpinsurer_Adm','recoveryagent')
GROUP BY R.Role ORDER BY R.Role;
