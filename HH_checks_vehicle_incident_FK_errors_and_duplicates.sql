/* =====================================================================================
   HOUSEHOLD CHECKS  (read-only, nothing is changed or deleted; for you and BA)
   Run the HH claim contact role proc first (IS_CLAIMCONTACTROLE must be loaded).

   V0      Look at IS_INCIDENT for household: which subtype values exist (confirms the column names the proc v2 uses)
   PART A  ERROR 1 for Household: exposure IncidentID is not found in IS_INCIDENT
   PART B  ERROR 2 for Household: claim contact role carries such an IncidentID
   PART C  Household third-party exposures that were not created
   CHECK 1 thirdparty_adm / tpinsurer_Adm / recoveryagent: does the contact's OWN case have a VehicleIncident at all?
   CHECK 2 two different claim contacts with the same role on the same exposure

   For Household ONLY the incident table is joined, because IS_EXPOSURE_HOUSEHOLD has no incident type column.
   The incident table is always joined on the incident ID that comes from IS_EXPOSURE_HOUSEHOLD, so only household incidents are read.
   If IS_INCIDENT has a Retired column add  AND ISNULL(I.Retired,0) = 0  to the incident joins.
   HH role PublicID = 'mig:hhccr' + HDR_ID + '_' + Role   (HDR_ID starts at character 10).
   ===================================================================================== */
USE IntermediateStaging_DEV;
GO

/* ============================ V0 - DOES THE INCIDENT TABLE HAVE WHAT THE PROC NEEDS ============================ */
-- V0a. the incident IDs used by household exposures, with the subtype found in IS_INCIDENT  (Subtype = NULL means not found in IS_INCIDENT)
SELECT CASE WHEN PATINDEX('%[0-9]%', E.IncidentID) > 0 THEN LEFT(E.IncidentID, PATINDEX('%[0-9]%', E.IncidentID) - 1) ELSE E.IncidentID END AS IncidentIdShape,
       I.Subtype AS Subtype_InIS_INCIDENT,
       COUNT(*) AS Exposures, COUNT(DISTINCT E.IncidentID) AS DistinctIncidents
FROM dbo.IS_EXPOSURE_HOUSEHOLD E
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = E.IncidentID
WHERE E.IncidentID IS NOT NULL
GROUP BY CASE WHEN PATINDEX('%[0-9]%', E.IncidentID) > 0 THEN LEFT(E.IncidentID, PATINDEX('%[0-9]%', E.IncidentID) - 1) ELSE E.IncidentID END, I.Subtype
ORDER BY Exposures DESC;
-- Expected: 'mig:HH_veh...' shapes show Subtype 'VehicleIncident'. If the Subtype column is named differently, or the vehicle shape shows another value,
-- tell me before the proc v2 is run (the proc filters  INC.Subtype = 'VehicleIncident').
-- If there is NO row with a 'mig:HH_veh' shape at all, Household has no vehicle incident in the data and all three roles will get no incident.

-- V0b. how many household exposures have no IncidentID at all (they can never give a role an incident)
SELECT COUNT(*) AS HouseholdExposures, SUM(CASE WHEN IncidentID IS NULL THEN 1 ELSE 0 END) AS ExposuresWithoutIncidentID FROM dbo.IS_EXPOSURE_HOUSEHOLD;


/* ============================ PART A - HH EXPOSURE INCIDENTID NOT IN IS_INCIDENT  (ERROR 1) ============================ */
IF OBJECT_ID('tempdb..#HA_MISS') IS NOT NULL DROP TABLE #HA_MISS;
SELECT CLM.CLAIM_REF                AS ClaimRef,
       CLM.GW_HDR_CASEID            AS GW_HDR_CASEID,
       E.VectusCaseID_Adm           AS CaseID,                 -- HHT.ID for third-party, HHB.ID buildings, HHC.ID contents
       E.PublicID                   AS ExposureID,
       E.LossParty                  AS LossParty,
       E.IncidentID                 AS IncidentID_FromExposure,
       'IncidentID on exposure is NOT FOUND in IS_INCIDENT' AS IncidentTableCheck
INTO #HA_MISS
FROM dbo.IS_EXPOSURE_HOUSEHOLD E
LEFT JOIN dbo.IS_INCIDENT I        ON I.PublicID = E.IncidentID
LEFT JOIN dbo.IS_CLAIM_MASTER CLM  ON CLM.PublicID = E.ClaimID
WHERE E.IncidentID IS NOT NULL
  AND I.PublicID IS NULL;
CREATE NONCLUSTERED INDEX IX_HA_MISS ON #HA_MISS (IncidentID_FromExposure);

-- A1. how big, by first party / third party
SELECT E.LossParty,
       COUNT(*) AS ExposuresWithIncidentID,
       SUM(CASE WHEN I.PublicID IS NULL THEN 1 ELSE 0 END)     AS 'IncidentID NOT FOUND in IS_INCIDENT',
       SUM(CASE WHEN I.PublicID IS NOT NULL THEN 1 ELSE 0 END) AS 'IncidentID found'
FROM dbo.IS_EXPOSURE_HOUSEHOLD E
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = E.IncidentID
WHERE E.IncidentID IS NOT NULL
GROUP BY E.LossParty ORDER BY 3 DESC;

-- A2. THE LIST: claim, GW header case ID, case ID, exposure, incident ID from the exposure, incident table result
SELECT ClaimRef, GW_HDR_CASEID, CaseID, ExposureID, LossParty, IncidentID_FromExposure, IncidentTableCheck
FROM #HA_MISS ORDER BY LossParty, ClaimRef;

-- A3. what the missing IDs look like (prefix before the number)
SELECT LEFT(IncidentID_FromExposure, CASE WHEN PATINDEX('%[0-9]%', IncidentID_FromExposure) > 0 THEN PATINDEX('%[0-9]%', IncidentID_FromExposure) - 1 ELSE LEN(IncidentID_FromExposure) END) AS IdPrefix,
       LossParty, COUNT(*) AS Exposures
FROM #HA_MISS
GROUP BY LEFT(IncidentID_FromExposure, CASE WHEN PATINDEX('%[0-9]%', IncidentID_FromExposure) > 0 THEN PATINDEX('%[0-9]%', IncidentID_FromExposure) - 1 ELSE LEN(IncidentID_FromExposure) END), LossParty
ORDER BY Exposures DESC;

-- A4. how do household incident IDs look in IS_INCIDENT (compare with A3: spelling / separator differences show up here)
SELECT TOP 20 PublicID, Subtype FROM dbo.IS_INCIDENT WHERE PublicID LIKE 'mig:HH%' OR PublicID LIKE 'mig:hh%' ORDER BY PublicID;


/* ============================ PART B - HH CLAIM CONTACT ROLES WITH SUCH AN INCIDENTID  (ERROR 2) ============================ */
IF OBJECT_ID('tempdb..#HB_MISS') IS NOT NULL DROP TABLE #HB_MISS;
SELECT R.PublicID AS RolePublicID, R.ClaimContactID, R.Role, R.ExposureID, R.IncidentID,
       TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 10, NULLIF(CHARINDEX('_', R.PublicID, 10), 0) - 10)) AS HDR_ID
INTO #HB_MISS
FROM dbo.IS_CLAIMCONTACTROLE R
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = R.IncidentID
WHERE R.PublicID LIKE 'mig:hhccr%' AND R.IncidentID IS NOT NULL AND I.PublicID IS NULL;

-- B1. by role
SELECT Role, COUNT(*) AS ContactRoleRows, COUNT(DISTINCT IncidentID) AS DistinctIncidentIDs FROM #HB_MISS GROUP BY Role ORDER BY ContactRoleRows DESC;

-- B2. proof that ERROR 2 comes from ERROR 1: role rows whose missing incident is also on a household exposure from Part A
SELECT SUM(CASE WHEN M.IncidentID_FromExposure IS NOT NULL THEN 1 ELSE 0 END) AS RowsWhoseIncidentIdIsOnAMissingExposureIncident,
       COUNT(*) AS AllRowsWithMissingIncident
FROM #HB_MISS B
LEFT JOIN (SELECT DISTINCT IncidentID_FromExposure FROM #HA_MISS) M ON M.IncidentID_FromExposure = B.IncidentID;

-- B3. THE LIST: claim, GW header case ID, case ID, role, contact, exposure, incident from the role row
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID, HDR.CASEID AS CaseID,
       B.Role, B.ClaimContactID, B.HDR_ID, B.ExposureID, B.IncidentID AS IncidentID_OnRole,
       'IncidentID is NOT FOUND in IS_INCIDENT' AS IncidentTableCheck
FROM #HB_MISS B
JOIN dbo.IS_CLAIMCONTACT CC ON CC.PublicID = B.ClaimContactID
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.PublicID = CC.ClaimID
LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = B.HDR_ID
ORDER BY B.Role, CLM.CLAIM_REF;


/* ============================ PART C - HH THIRD-PARTY CASES WITHOUT ANY EXPOSURE ============================
   Colleague's logic: only VEC_HH_THIRDPARTY cases with CLAIM_RECOVERY = 'TP' create an exposure; the build has INNER JOINs on
   VEC_HH_INC_DETS, VEC_GW_CASE_STATUS, VEC_CASE and IS_COVERAGE, any of which can remove a case.  REC cases never create one (BA decision pending). */
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID, HT.ID AS CaseID, HT.CLAIM_RECOVERY AS CaseType,
       CASE WHEN HT.CLAIM_RECOVERY = 'REC' THEN 'REC case - creates no exposure by design' ELSE 'TP case - NO exposure created' END AS Reason
FROM SourceStaging.VECCASRN.VEC_HH_THIRDPARTY HT
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.GW_HDR_CASEID = HT.HH_CLAIMID AND CLM.PRODUCT = 'HOUSEHOLD'
WHERE NOT EXISTS (SELECT 1 FROM dbo.IS_EXPOSURE_HOUSEHOLD E WHERE CONVERT(VARCHAR(64), E.VectusCaseID_Adm) = CONVERT(VARCHAR(64), HT.ID))
ORDER BY HT.CLAIM_RECOVERY, CLM.CLAIM_REF;


/* ============================ CHECK 1 - DOES THE OWN CASE HAVE A VEHICLE INCIDENT? ============================
   Roles: thirdparty_adm, tpinsurer_Adm, recoveryagent  (Guidewire accepts them only on a VehicleIncident).
   Only the contact's OWN case is looked at (VectusCaseID_Adm = case ID of the contact). No claim-level fallback, nothing is deleted.
   Reason (first one that applies):
     P1  the case has NO exposure at all (no exposure row for this case ID)
     P2  the case has exposures but NONE has an IncidentID
     P3  the case has incidents, but NONE of them is a VehicleIncident in IS_INCIDENT (or the incident is not found in IS_INCIDENT)
     OK  the case has a VehicleIncident                                                                                             */
IF OBJECT_ID('tempdb..#HV_ROLE') IS NOT NULL DROP TABLE #HV_ROLE;
SELECT R.Role, R.ClaimContactID, R.ExposureID AS ExposureOnRole, R.IncidentID AS IncidentOnRole,
       TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 10, NULLIF(CHARINDEX('_', R.PublicID, 10), 0) - 10)) AS HDR_ID
INTO #HV_ROLE
FROM dbo.IS_CLAIMCONTACTROLE R
WHERE R.PublicID LIKE 'mig:hhccr%' AND R.Role IN ('thirdparty_adm','tpinsurer_Adm','recoveryagent');

-- exposures and incidents of each case (own case only), with the subtype from IS_INCIDENT
IF OBJECT_ID('tempdb..#HV_CASEINC') IS NOT NULL DROP TABLE #HV_CASEINC;
SELECT DISTINCT CONVERT(VARCHAR(64), E.VectusCaseID_Adm) AS CaseID, E.PublicID AS ExposureID, E.IncidentID, I.Subtype
INTO #HV_CASEINC
FROM dbo.IS_EXPOSURE_HOUSEHOLD E
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = E.IncidentID
WHERE E.VectusCaseID_Adm IS NOT NULL;
CREATE CLUSTERED INDEX IX_HV_CASEINC ON #HV_CASEINC (CaseID);

-- one row per case with the counts
IF OBJECT_ID('tempdb..#HV_CASE') IS NOT NULL DROP TABLE #HV_CASE;
SELECT CaseID,
       COUNT(DISTINCT ExposureID) AS Exposures,
       COUNT(DISTINCT IncidentID) AS Incidents,
       COUNT(DISTINCT CASE WHEN Subtype = 'VehicleIncident' THEN IncidentID END) AS VehicleIncidents,
       STRING_AGG(CONVERT(VARCHAR(MAX), ExposureID + ' -> ' + ISNULL(IncidentID, '(no IncidentID)') + ' [' + ISNULL(Subtype, 'not found in IS_INCIDENT') + ']'), ' ; ') AS CaseExposuresAndIncidents
INTO #HV_CASE
FROM #HV_CASEINC GROUP BY CaseID;
CREATE UNIQUE CLUSTERED INDEX IX_HV_CASE ON #HV_CASE (CaseID);

IF OBJECT_ID('tempdb..#HV_PROB') IS NOT NULL DROP TABLE #HV_PROB;
SELECT T.Role, T.ClaimContactID, T.HDR_ID, T.ExposureOnRole, T.IncidentOnRole,
       HDR.CASEID AS CaseID, HDR.CASEID AS HDR_CASEID_RAW, HT.HH_CLAIMID, HT.CLAIM_RECOVERY AS CaseType,
       ISNULL(C.Exposures, 0) AS Exposures, ISNULL(C.Incidents, 0) AS Incidents, ISNULL(C.VehicleIncidents, 0) AS VehicleIncidents,
       C.CaseExposuresAndIncidents,
       CASE WHEN C.CaseID IS NULL           THEN 'P1 - the case has NO exposure'
            WHEN C.Incidents = 0            THEN 'P2 - the case has exposure(s) but none has an IncidentID'
            WHEN C.VehicleIncidents = 0     THEN 'P3 - the case has incidents but none is a VehicleIncident'
            ELSE 'OK - the case has a VehicleIncident' END AS Situation
INTO #HV_PROB
FROM #HV_ROLE T
JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = T.HDR_ID
LEFT JOIN SourceStaging.VECCASRN.VEC_HH_THIRDPARTY HT ON HT.ID = HDR.CASEID
LEFT JOIN #HV_CASE C ON C.CaseID = CONVERT(VARCHAR(64), HDR.CASEID);

-- 1a. SUMMARY by role and situation (role rows and distinct cases)
SELECT Role, Situation, COUNT(*) AS RoleRows, COUNT(DISTINCT CaseID) AS Cases
FROM #HV_PROB GROUP BY Role, Situation ORDER BY Role, Situation;

-- 1b. THE LIST for BA: claim, GW header case ID, case ID, role, situation, the case's own exposures / incidents / subtype
--     (@Role: 'thirdparty_adm' / 'tpinsurer_Adm' / 'recoveryagent' or NULL for all;   @OnlyProblems = 1 hides the OK rows)
DECLARE @Role VARCHAR(60) = NULL, @OnlyProblems BIT = 1;
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID, P.CaseID AS CaseID, P.CaseType,
       P.Role, P.ClaimContactID, P.Situation,
       P.CaseExposuresAndIncidents AS 'Own case: exposure -> incident [subtype in IS_INCIDENT]',
       P.ExposureOnRole AS 'Exposure now on the role row', P.IncidentOnRole AS 'Incident now on the role row'
FROM #HV_PROB P
LEFT JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.GW_HDR_CASEID = P.HH_CLAIMID AND CLM.PRODUCT = 'HOUSEHOLD'
WHERE (@Role IS NULL OR P.Role = @Role)
  AND (@OnlyProblems = 0 OR P.Situation NOT LIKE 'OK%')
ORDER BY P.Role, P.Situation, CLM.CLAIM_REF;

-- 1c. one case in full (put a case ID in @CaseID): every exposure and incident of that case
DECLARE @CaseID VARCHAR(64) = NULL;
SELECT CaseID, ExposureID, IncidentID, ISNULL(Subtype, 'not found in IS_INCIDENT') AS Subtype FROM #HV_CASEINC WHERE @CaseID IS NOT NULL AND CaseID = @CaseID ORDER BY ExposureID;


/* ============================ CHECK 2 - SAME ROLE, SAME EXPOSURE, DIFFERENT CLAIM CONTACTS ============================ */
IF OBJECT_ID('tempdb..#HD_ROLE') IS NOT NULL DROP TABLE #HD_ROLE;
SELECT R.Role, R.ExposureID, R.ClaimContactID,
       TRY_CONVERT(BIGINT, SUBSTRING(R.PublicID, 10, NULLIF(CHARINDEX('_', R.PublicID, 10), 0) - 10)) AS HDR_ID
INTO #HD_ROLE
FROM dbo.IS_CLAIMCONTACTROLE R
WHERE R.PublicID LIKE 'mig:hhccr%' AND R.ExposureID IS NOT NULL;

IF OBJECT_ID('tempdb..#HD_GROUP') IS NOT NULL DROP TABLE #HD_GROUP;
SELECT ExposureID, Role, COUNT(DISTINCT ClaimContactID) AS ClaimContacts
INTO #HD_GROUP
FROM #HD_ROLE GROUP BY ExposureID, Role HAVING COUNT(DISTINCT ClaimContactID) > 1;

-- 2a. SUMMARY by role
SELECT Role, COUNT(*) AS ExposureRoleGroups, SUM(ClaimContacts) AS ClaimContactsInvolved FROM #HD_GROUP GROUP BY Role ORDER BY ExposureRoleGroups DESC;

-- 2b. THE LIST: claim, GW header case ID, case ID(s) of the contacts, exposure, role, the claim contacts
--     (@DRole: one role or NULL for all)
DECLARE @DRole VARCHAR(60) = NULL;
SELECT CLM.CLAIM_REF AS ClaimRef, CLM.GW_HDR_CASEID AS GW_HDR_CASEID,
       STRING_AGG(CONVERT(VARCHAR(MAX), X.CaseID), ', ') AS CaseIDs_OfTheContacts,
       G.ExposureID, G.Role, G.ClaimContacts AS NumberOfClaimContacts,
       STRING_AGG(CONVERT(VARCHAR(MAX), X.ClaimContactID), ', ') AS ClaimContactIDs
FROM #HD_GROUP G
JOIN (SELECT DISTINCT D.ExposureID, D.Role, D.ClaimContactID, HDR.CASEID AS CaseID, CC.ClaimID
      FROM #HD_ROLE D
      JOIN dbo.IS_CLAIMCONTACT CC ON CC.PublicID = D.ClaimContactID
      LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = D.HDR_ID) X
  ON X.ExposureID = G.ExposureID AND X.Role = G.Role
JOIN dbo.IS_CLAIM_MASTER CLM ON CLM.PublicID = X.ClaimID
WHERE @DRole IS NULL OR G.Role = @DRole
GROUP BY CLM.CLAIM_REF, CLM.GW_HDR_CASEID, G.ExposureID, G.Role, G.ClaimContacts
ORDER BY G.Role, CLM.CLAIM_REF;
