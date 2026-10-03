/* =====================================================================================
   BA EVIDENCE PACK - MOTOR - CLAIM CONTACT ROLES   (IS layer only)
   Replaces the earlier BA_evidence_* files.

   PURPOSE
   The load proc does NOT delete or skip any role because of a business problem.
   Where something cannot be linked, the role is still created (claim-only) and the claim is
   listed here, so the Business Analyst can decide what to do.

   HOW TO RUN
   1) Run the SETUP block once (it builds temp tables, a few minutes on 14M contacts).
   2) Run Q0 first (one-page summary), then any detail query Q1..Q8.
   3) Q4 and Q5 read the table the proc loaded (IS_CLAIMCONTACTROLE), so run the proc first.

   WHAT THE PROC DOES TODAY FOR EACH SITUATION (so BA can see the current behaviour)
   S1  Roles that must link to the vehicle incident (repairshop, hirecompany_adm, thirdparty_adm,
       tpinsurer_Adm, recoveryagent) but the TP case has no VehicleIncident
           -> role is KEPT, claim-only (IncidentID and ExposureID empty).   Listed in Q1/Q2.
   S2  Role expects an incident but the TP case has no incident at all
           -> role is KEPT, claim-only.                                      Listed in Q1/Q2.
   S3  Role expects an exposure but there is none to link to
           -> role is KEPT with ExposureID empty.                            Listed in Q3.
   S4  Two different contacts with the same role on the same incident / exposure
           -> BOTH are loaded (nothing removed). Guidewire's exclusive-role rule will reject
              one of them. Listed in Q4 / Q5 as bugs for BA.
   S5  Several incident / exposure types on one TP case (injury, property, vehicle ...)
           -> BA rule: link to any one of them (lowest ID). The 5 roles above must use the
              vehicle incident and its exposure.                             Shown in Q6.
   S6  Contacts whose header type + link type has no row in the roles lookup
           -> no role row can be built for them (nothing to assign). Listed in Q7.

   NAMES ASSUMED (rename if different):  IS_INCIDENT.Subtype, IS_EXPOSURE_MOTOR.IncidentID /
   VectusCaseID_Adm / SourceOrigin_Adm / ClaimID, IS_CLAIMCONTACTROLE.LUWID (= claim reference)
   ===================================================================================== */
USE IntermediateStaging_DEV;
GO

/* ============================== SETUP ============================== */
IF OBJECT_ID('tempdb..#S_BASE')      IS NOT NULL DROP TABLE #S_BASE;
IF OBJECT_ID('tempdb..#S_CASE_TYPES')IS NOT NULL DROP TABLE #S_CASE_TYPES;
IF OBJECT_ID('tempdb..#S_CASE')      IS NOT NULL DROP TABLE #S_CASE;
IF OBJECT_ID('tempdb..#S_CLAIMEXP')  IS NOT NULL DROP TABLE #S_CLAIMEXP;
IF OBJECT_ID('tempdb..#S_PICK')      IS NOT NULL DROP TABLE #S_PICK;

/* 1. Every Motor claim contact with the role the lookup gives it (same joins as the proc, one row per
      contact / header / link type). Role is NULL when the lookup has no row. */
SELECT DISTINCT
       CLM.PublicID                       AS ClaimPublicID,
       C.CLAIM_REF,
       CC.PublicID                        AS ClaimContactID,
       C.PublicID                         AS ContactPublicID,
       C.HDR_ID, C.HDR_TYPE_ID, C.LINK_TYPE_ID,
       CONVERT(VARCHAR(64), HDR.CASEID)   AS CaseID,              -- TP.ID for TP contacts
       L.GWCC_Role_TYPECODE               AS Role,
       L.Link_to_Exposure, L.Link_to_Incident,
       L.EXPOSURE                         AS LookupExposureText
INTO #S_BASE
FROM dbo.CONTACT_MASTER_MOTOR C
JOIN dbo.IS_CLAIM_MASTER  CLM ON C.GW_HDR_CASEID = CLM.GW_HDR_CASEID AND CLM.PRODUCT = 'MOTOR'
JOIN dbo.IS_CLAIMCONTACT  CC  ON CC.ContactID = C.PublicID AND CC.ClaimID = CLM.PublicID
LEFT JOIN SourceStaging.VECCASRN.VEC_GW_CF_HDR HDR ON HDR.ID = C.HDR_ID
LEFT JOIN dbo.CLAIM_CONTACT_ROLE_LOOKUP L
       ON  L.PRODUCT = 'Motor'
       AND L.HDR_TYPEID  = C.HDR_TYPE_ID
       AND L.LINK_TYPEID = C.LINK_TYPE_ID;
CREATE NONCLUSTERED INDEX IX_S_BASE ON #S_BASE (CaseID);

/* 2. What each TP case produced: incident types, and the incident the proc picks */
SELECT CONVERT(VARCHAR(64), E.VectusCaseID_Adm) AS CaseID,
       ISNULL(I.Subtype, 'unknown')             AS Subtype,
       COUNT(DISTINCT E.IncidentID)             AS Incidents
INTO #S_CASE_TYPES
FROM dbo.IS_EXPOSURE_MOTOR E
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = E.IncidentID
WHERE E.SourceOrigin_Adm IN ('TP_VEH','TP_INJ','TP_PRO','TP_HIRE')
  AND E.IncidentID IS NOT NULL
GROUP BY CONVERT(VARCHAR(64), E.VectusCaseID_Adm), ISNULL(I.Subtype, 'unknown');

SELECT CONVERT(VARCHAR(64), E.VectusCaseID_Adm)               AS CaseID,
       COUNT(DISTINCT E.Exposure_Motor_PublicID)              AS Exposures,
       COUNT(DISTINCT E.IncidentID)                           AS Incidents,
       COUNT(DISTINCT CASE WHEN I.Subtype = 'VehicleIncident' THEN E.IncidentID END) AS VehicleIncidents,
       MIN(E.IncidentID)                                      AS PickedAnyIncident,       -- what the proc uses for ordinary roles
       MIN(CASE WHEN I.Subtype = 'VehicleIncident' THEN E.IncidentID END) AS PickedVehicleIncident  -- what the proc uses for the 5 roles
INTO #S_CASE
FROM dbo.IS_EXPOSURE_MOTOR E
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = E.IncidentID
WHERE E.SourceOrigin_Adm IN ('TP_VEH','TP_INJ','TP_PRO','TP_HIRE')
GROUP BY CONVERT(VARCHAR(64), E.VectusCaseID_Adm);
CREATE UNIQUE CLUSTERED INDEX IX_S_CASE ON #S_CASE (CaseID);

/* incident types on the case as one readable text, e.g. 'InjuryIncident x1, VehicleIncident x1' */
ALTER TABLE #S_CASE ADD TypesOnCase VARCHAR(400) NULL;
UPDATE C SET TypesOnCase = T.Txt
FROM #S_CASE C
JOIN (SELECT CaseID, STRING_AGG(Subtype + ' x' + CONVERT(VARCHAR(10), Incidents), ', ') AS Txt
      FROM #S_CASE_TYPES GROUP BY CaseID) T ON T.CaseID = C.CaseID;

/* 3. 1st-party exposures per claim (AD and PA) */
SELECT ClaimID,
       SUM(CASE WHEN SourceOrigin_Adm = 'AD' THEN 1 ELSE 0 END)                 AS AD_Exposures,
       SUM(CASE WHEN SourceOrigin_Adm IN ('PA','PA_PLUS') THEN 1 ELSE 0 END)    AS PA_Exposures
INTO #S_CLAIMEXP
FROM dbo.IS_EXPOSURE_MOTOR
GROUP BY ClaimID;
CREATE UNIQUE CLUSTERED INDEX IX_S_CLAIMEXP ON #S_CLAIMEXP (ClaimID);

/* 4. Contacts whose role expects an INCIDENT: what the proc picks and whether it found one */
SELECT B.ClaimPublicID, B.CLAIM_REF, B.ClaimContactID, B.ContactPublicID, B.HDR_ID,
       B.HDR_TYPE_ID, B.LINK_TYPE_ID, B.CaseID, B.Role,
       CASE WHEN B.Role IN ('repairshop','hirecompany_adm','thirdparty_adm','tpinsurer_Adm','recoveryagent')
            THEN 'MUST be VehicleIncident' ELSE 'any incident of the case' END   AS RuleForRole,
       ISNULL(C.Incidents, 0)                                                     AS IncidentsOnCase,
       ISNULL(C.VehicleIncidents, 0)                                              AS VehicleIncidentsOnCase,
       C.TypesOnCase,
       CASE WHEN B.Role IN ('repairshop','hirecompany_adm','thirdparty_adm','tpinsurer_Adm','recoveryagent')
            THEN C.PickedVehicleIncident ELSE C.PickedAnyIncident END             AS PickedIncidentID
INTO #S_PICK
FROM #S_BASE B
LEFT JOIN #S_CASE C ON C.CaseID = B.CaseID
WHERE B.Link_to_Incident = 'YES';
/* ============================ END SETUP ============================ */


/* =====================================================================================
   Q0 - ONE-PAGE SUMMARY FOR BA  (how many claims are affected by each situation)
   ===================================================================================== */
SELECT 'S1  Must link to VehicleIncident but the TP case has none (only other incident types)' AS Situation,
       COUNT(*) AS ContactRoleRows, COUNT(DISTINCT CLAIM_REF) AS Claims
FROM #S_PICK WHERE RuleForRole = 'MUST be VehicleIncident' AND PickedIncidentID IS NULL AND IncidentsOnCase > 0
UNION ALL
SELECT 'S2  Role expects an incident but the TP case has no incident at all', COUNT(*), COUNT(DISTINCT CLAIM_REF)
FROM #S_PICK WHERE PickedIncidentID IS NULL AND IncidentsOnCase = 0
UNION ALL
SELECT 'S3  Role expects an exposure but there is none to link to', COUNT(*), COUNT(DISTINCT CLAIM_REF)
FROM #S_BASE B
LEFT JOIN #S_CASE    C  ON C.CaseID = B.CaseID
LEFT JOIN #S_CLAIMEXP X ON X.ClaimID = B.ClaimPublicID
WHERE B.Link_to_Exposure = 'YES'
  AND ( (UPPER(B.LookupExposureText) LIKE '%THIRDPARTY%' AND ISNULL(C.Exposures,0) = 0)
     OR (UPPER(B.LookupExposureText) LIKE '%ANCILLARY%'  AND ISNULL(X.PA_Exposures,0) = 0)
     OR (UPPER(B.LookupExposureText) LIKE '%MOTOR AD%'   AND ISNULL(X.AD_Exposures,0) = 0) )
UNION ALL
SELECT 'S4a Two or more contacts, same role, same incident (loaded, will clash in Guidewire)', COUNT(*), COUNT(DISTINCT ClaimRef)
FROM (SELECT R.LUWID AS ClaimRef, R.Role, R.IncidentID
      FROM dbo.IS_CLAIMCONTACTROLE R
      WHERE R.PublicID LIKE 'mig:motorccr%' AND R.IncidentID IS NOT NULL
      GROUP BY R.LUWID, R.Role, R.IncidentID HAVING COUNT(DISTINCT R.ClaimContactID) > 1) D
UNION ALL
SELECT 'S4b Two or more contacts, same role, same exposure (claimant must be unique per exposure)', COUNT(*), COUNT(DISTINCT ClaimRef)
FROM (SELECT R.LUWID AS ClaimRef, R.Role, R.ExposureID
      FROM dbo.IS_CLAIMCONTACTROLE R
      WHERE R.PublicID LIKE 'mig:motorccr%' AND R.ExposureID IS NOT NULL
      GROUP BY R.LUWID, R.Role, R.ExposureID HAVING COUNT(DISTINCT R.ClaimContactID) > 1) D
UNION ALL
SELECT 'S6  Contact rows with no role in the lookup (no role row can be built)', COUNT(*), COUNT(DISTINCT CLAIM_REF)
FROM #S_BASE WHERE Role IS NULL;


/* =====================================================================================
   Q1 - ROLES THAT LINK TO AN INCIDENT: WHAT WE FOUND ON THEIR TP CASES   (all such roles)
   Reading guide: one row per role. 'LinkOK' = an acceptable incident exists and is used.
   The 5 vehicle roles need a VehicleIncident; every other incident-linked role may use any incident.
   ===================================================================================== */
SELECT Role, RuleForRole,
       COUNT(*)                                                                   AS ContactRoleRows,
       COUNT(DISTINCT CLAIM_REF)                                                  AS Claims,
       SUM(CASE WHEN PickedIncidentID IS NOT NULL THEN 1 ELSE 0 END)              AS LinkOK,
       SUM(CASE WHEN PickedIncidentID IS NULL AND IncidentsOnCase > 0 THEN 1 ELSE 0 END) AS NoVehicleIncident_OnlyOtherTypes,
       SUM(CASE WHEN PickedIncidentID IS NULL AND IncidentsOnCase = 0 THEN 1 ELSE 0 END) AS CaseHasNoIncidentAtAll
FROM #S_PICK
GROUP BY Role, RuleForRole
ORDER BY RuleForRole DESC, Role;


/* =====================================================================================
   Q2 - THE CLAIMS TO SEND TO BA FOR S1 / S2   (role could not be linked to an incident)
   Each row is one contact. 'IncidentTypesOnCase' shows what the TP case actually has.
   ===================================================================================== */
SELECT P.CLAIM_REF                   AS ClaimRef,
       P.CaseID                      AS TP_CaseID,
       P.HDR_ID, P.ContactPublicID, P.HDR_TYPE_ID, P.LINK_TYPE_ID,
       P.Role,
       P.RuleForRole,
       ISNULL(P.TypesOnCase, '(no incident on this case)') AS IncidentTypesOnCase,
       CASE WHEN P.IncidentsOnCase = 0
            THEN 'S2 - TP case has no incident'
            ELSE 'S1 - TP case has no VehicleIncident' END AS Situation,
       'Role KEPT, linked to claim only (IncidentID and ExposureID empty)' AS WhatTheLoadDoes
FROM #S_PICK P
WHERE P.PickedIncidentID IS NULL
ORDER BY Situation, P.Role, P.CLAIM_REF, P.CaseID;


/* =====================================================================================
   Q3 - S3: ROLE EXPECTS AN EXPOSURE BUT THERE IS NONE TO LINK TO
   ===================================================================================== */
SELECT B.CLAIM_REF AS ClaimRef, B.CaseID AS CaseID, B.HDR_ID, B.ContactPublicID, B.Role,
       B.LookupExposureText AS LookupSaysLinkTo,
       CASE WHEN UPPER(B.LookupExposureText) LIKE '%THIRDPARTY%' THEN 'TP case ' + B.CaseID + ' has no TP exposure'
            WHEN UPPER(B.LookupExposureText) LIKE '%ANCILLARY%'  THEN 'Claim has no PA (ancillary) exposure'
            WHEN UPPER(B.LookupExposureText) LIKE '%MOTOR AD%'   THEN 'Claim has no AD exposure' END AS WhyNoTarget,
       'Role KEPT, ExposureID empty' AS WhatTheLoadDoes
FROM #S_BASE B
LEFT JOIN #S_CASE    C ON C.CaseID = B.CaseID
LEFT JOIN #S_CLAIMEXP X ON X.ClaimID = B.ClaimPublicID
WHERE B.Link_to_Exposure = 'YES'
  AND ( (UPPER(B.LookupExposureText) LIKE '%THIRDPARTY%' AND ISNULL(C.Exposures,0) = 0)
     OR (UPPER(B.LookupExposureText) LIKE '%ANCILLARY%'  AND ISNULL(X.PA_Exposures,0) = 0)
     OR (UPPER(B.LookupExposureText) LIKE '%MOTOR AD%'   AND ISNULL(X.AD_Exposures,0) = 0) )
ORDER BY B.Role, B.CLAIM_REF;


/* =====================================================================================
   Q4 - S4: SAME ROLE, SAME INCIDENT, MORE THAN ONE CONTACT   (read from the loaded table, ALL roles)
   Nothing was removed. Guidewire allows only one contact per incident for some roles
   (load errors seen so far: recoveryagent and tpinsurer_Adm). Other roles are listed too,
   because BA has not given a full list of which roles are exclusive.
   ===================================================================================== */
-- Q4a: summary by role
SELECT R.Role,
       CASE WHEN R.Role IN ('recoveryagent','tpinsurer_Adm')
            THEN 'YES - Guidewire load error seen' ELSE 'not seen yet - BA to confirm' END AS GuidewireRejectsDuplicates,
       COUNT(*) AS IncidentsWithMoreThanOneContact, COUNT(DISTINCT D.ClaimRef) AS Claims
FROM (SELECT R2.LUWID AS ClaimRef, R2.Role, R2.IncidentID
      FROM dbo.IS_CLAIMCONTACTROLE R2
      WHERE R2.PublicID LIKE 'mig:motorccr%' AND R2.IncidentID IS NOT NULL
      GROUP BY R2.LUWID, R2.Role, R2.IncidentID HAVING COUNT(DISTINCT R2.ClaimContactID) > 1) D
JOIN (SELECT DISTINCT Role FROM dbo.IS_CLAIMCONTACTROLE WHERE PublicID LIKE 'mig:motorccr%') R ON R.Role = D.Role
GROUP BY R.Role
ORDER BY COUNT(*) DESC;

-- Q4b: the claims (send to BA)
SELECT R.LUWID AS ClaimRef, R.Role, R.IncidentID, I.Subtype AS IncidentSubtype,
       COUNT(DISTINCT R.ClaimContactID)                                   AS ContactsOnSameIncident,
       STRING_AGG(CONVERT(VARCHAR(100), R.ClaimContactID), ', ')           AS ClaimContacts,
       'BUG - loaded as is, not removed; needs a business decision'        AS Status
FROM dbo.IS_CLAIMCONTACTROLE R
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = R.IncidentID
WHERE R.PublicID LIKE 'mig:motorccr%' AND R.IncidentID IS NOT NULL
GROUP BY R.LUWID, R.Role, R.IncidentID, I.Subtype
HAVING COUNT(DISTINCT R.ClaimContactID) > 1
ORDER BY R.Role, R.LUWID;


/* =====================================================================================
   Q5 - S4b: SAME ROLE, SAME EXPOSURE, MORE THAN ONE CONTACT  (claimant is exclusive per exposure)
   ===================================================================================== */
SELECT R.LUWID AS ClaimRef, R.Role, R.ExposureID,
       COUNT(DISTINCT R.ClaimContactID)                          AS ContactsOnSameExposure,
       STRING_AGG(CONVERT(VARCHAR(100), R.ClaimContactID), ', ')  AS ClaimContacts,
       CASE WHEN R.Role = 'claimant' THEN 'BA rule: claimant is exclusive per exposure'
            ELSE 'not confirmed as exclusive - BA to confirm' END AS Note
FROM dbo.IS_CLAIMCONTACTROLE R
WHERE R.PublicID LIKE 'mig:motorccr%' AND R.ExposureID IS NOT NULL
GROUP BY R.LUWID, R.Role, R.ExposureID
HAVING COUNT(DISTINCT R.ClaimContactID) > 1
ORDER BY R.Role, R.LUWID;


/* =====================================================================================
   Q6 - S5: TP CASES WITH SEVERAL INCIDENT TYPES - WHICH ONE THE LOAD PICKS
   BA rule: 'if more than one exposure/incident is created from one case it is enough to link to one'.
   Matrix: role (incident-linked) x subtype of the picked incident.
   The 5 vehicle roles should only ever show VehicleIncident here.
   ===================================================================================== */
SELECT P.Role, ISNULL(I.Subtype, '(none picked)') AS PickedIncidentSubtype,
       COUNT(*) AS ContactRoleRows, COUNT(DISTINCT P.CLAIM_REF) AS Claims,
       SUM(CASE WHEN P.IncidentsOnCase > 1 THEN 1 ELSE 0 END) AS RowsWhereCaseHadSeveralIncidents
FROM #S_PICK P
LEFT JOIN dbo.IS_INCIDENT I ON I.PublicID = P.PickedIncidentID
GROUP BY P.Role, ISNULL(I.Subtype, '(none picked)')
ORDER BY P.Role, ContactRoleRows DESC;

-- Q6b: examples: ordinary (non-vehicle) roles whose picked incident is NOT a VehicleIncident
-- Guidewire has not complained about these yet; BA may want to confirm the roles are allowed on that subtype.
SELECT TOP 200 P.CLAIM_REF AS ClaimRef, P.CaseID AS TP_CaseID, P.Role, P.TypesOnCase, I.Subtype AS PickedSubtype, P.PickedIncidentID
FROM #S_PICK P
JOIN dbo.IS_INCIDENT I ON I.PublicID = P.PickedIncidentID
WHERE P.RuleForRole = 'any incident of the case' AND I.Subtype <> 'VehicleIncident'
ORDER BY P.Role, P.CLAIM_REF;


/* =====================================================================================
   Q7 - S6: CONTACTS WITH NO ROLE IN THE LOOKUP  (header type + link type combinations)
   ===================================================================================== */
SELECT HDR_TYPE_ID, LINK_TYPE_ID, COUNT(*) AS ContactRows, COUNT(DISTINCT CLAIM_REF) AS Claims, MIN(CLAIM_REF) AS ExampleClaim
FROM #S_BASE WHERE Role IS NULL
GROUP BY HDR_TYPE_ID, LINK_TYPE_ID
ORDER BY ContactRows DESC;


/* =====================================================================================
   Q8 - ONE CLAIM, END TO END (put a claim reference in @ClaimRef to walk BA through it)
   ===================================================================================== */
DECLARE @ClaimRef VARCHAR(100) = '<CLAIM_REF>';
SELECT 'Contacts and roles on the claim' AS Section, B.CLAIM_REF, B.CaseID, B.HDR_ID, B.ContactPublicID, B.Role,
       B.Link_to_Incident, B.Link_to_Exposure
FROM #S_BASE B WHERE B.CLAIM_REF = @ClaimRef;

SELECT 'Incident types on each TP case of the claim' AS Section, B.CaseID, C.Exposures, C.Incidents, C.VehicleIncidents, C.TypesOnCase
FROM (SELECT DISTINCT CaseID FROM #S_BASE WHERE CLAIM_REF = @ClaimRef) B
LEFT JOIN #S_CASE C ON C.CaseID = B.CaseID;

SELECT 'What was loaded' AS Section, R.LUWID AS CLAIM_REF, R.ClaimContactID, R.Role, R.ExposureID, R.IncidentID
FROM dbo.IS_CLAIMCONTACTROLE R WHERE R.LUWID = @ClaimRef;
