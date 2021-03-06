/*SQL script for getting devoicing data from the CSJ RDB
  James Tanner June 2020
*/

/*Quickly check if the MoraPhones table exists,
  and delete it if so*/
DROP TABLE IF EXISTS MoraPhones;

/*First make a table of moras mapped to phones.
  Want to have one row per mora, and columns
  refer to the mora shape, its component phones,
  and unique IDs*/
CREATE TABLE MoraPhones AS
    SELECT
        segMora.MoraEntity, segMora.MoraID AS MoraPhoneID,
        Phone1.PhonemeEntity AS Phone1Phone, Phone1.PhonemeID AS Phone1ID,
        Phone2.PhonemeEntity AS Phone2Phone, Phone2.PhonemeID AS Phone2ID

    /*Because of no PIVOT in SQLite, need to do multiple joins of the
      phoneme table, making separate columns of each phoneme-ID pair.*/
    FROM segMora, relPhoneme2Mora AS MoraPhone1, relPhoneme2Mora AS MoraPhone2
    INNER JOIN segPhoneme AS Phone1 ON
        MoraPhone1.MoraID = segMora.MoraID AND
        MoraPhone1.PhonemeID = Phone1.PhonemeID AND
        MoraPhone1.TalkID = segMora.TalkID AND
        MoraPhone1.TalkID = Phone1.TalkID AND
        MoraPhone1.nth = 1
    INNER JOIN segPhoneme AS Phone2 ON
        MoraPhone2.MoraID = segMora.MoraID AND
        MoraPhone2.PhonemeID = Phone2.PhonemeID AND
        MoraPhone2.TalkID = segMora.TalkID AND
        MoraPhone2.TalkID = Phone2.TalkID AND
        MoraPhone2.nth = 2
    WHERE MoraPhone1.len = 2
    GROUP BY segMora.MoraID;

/*Main Query*/
CREATE TABLE DevoicingQuery AS
SELECT DISTINCT
        /*Phoneme columns*/
        segPhoneme.PhonemeID AS PhonemeID, segPhoneme.PhonemeEntity AS Phoneme,
        segPhoneme.StartTime AS PhonemeStart, segPhoneme.EndTime AS PhonemeEnd,
        segPhoneme.EndTime - segPhoneme.StartTime AS PhonemeDur,
        segPhone.Devoiced AS Devoiced,

        /*Mora columns*/
        segMora.MoraEntity AS Mora,
        segMora.StartTime AS MoraStart, segMora.EndTime AS MoraEnd,
        segMora.EndTime - segMora.StartTime AS MoraDur,

        /*Previous phoneme*/
        MoraPhones.Phone1Phone AS PrevPhoneme,

        /*Following mora*/
        FolMora AS FollowingMora,

        /*Word information*/
        segSUW.OrthographicTranscription AS Word,
        segSUW.StartTime AS WordStart, segSUW.EndTime AS WordEnd,
        segSUW.EndTime - segSUW.StartTime AS WordDur,

        /*Prosodic information*/
        segAP.FBT AS BoundaryTone,

        /*Check if the mora is at the edge of a prosodic boundary*/
        CAST(CASE
            WHEN relMora2AP.len = relMora2AP.nth
                THEN segAP.Break
            ELSE 0
            END AS TEXT) AS BreakIndex,

        /*Calculate speech rate as moras/sec within an IPU*/
        relMora2IPU.len / (segIPU.EndTime - segIPU.StartTime) AS IPUSpeechRate,

        /*Speaker infomation*/
        segPhone.TalkID AS TalkID, infoTalk.SpeakerID AS SpeakerID,
        infoTalk.SpeakerAge AS Age,
        infoSpeaker.SpeakerSex AS Gender, infoSpeaker.SpeakerBirthGeneration AS Generation,
        infoSpeaker.SpeakerBirthPlace AS Birthplace

    /*Get relations between tables.
      Because segment IDs are only unique within
      a given TalkID, it's necessary to also use
      TalkID as a join condition*/    
    FROM segPhone, relPhone2Phoneme, relPhoneme2Mora, relMora2AP, relMora2SUW, relMora2IPU
    INNER JOIN segPhoneme ON
                relPhone2Phoneme.PhonemeID = segPhoneme.PhonemeID AND
                relPhone2Phoneme.PhoneID = segPhone.PhoneID AND
                segPhoneme.TalkID = relPhone2Phoneme.TalkID AND
                segPhone.TalkID = relPhone2Phoneme.TalkID
    INNER JOIN segMora ON
                relPhoneme2Mora.MoraID = segMora.MoraID AND
                relPhoneme2Mora.PhonemeID = segPhoneme.PhonemeID AND
                relPhoneme2Mora.TalkID = segMora.TalkID AND
                relPhoneme2Mora.TalkID = segPhoneme.TalkID
    INNER JOIN segAP ON
                relMora2AP.APID = segAP.APID AND
                relMora2AP.MoraID = segMora.MoraID AND
                relMora2AP.TalkID = segAP.TalkID AND
                relMora2AP.TalkID = segMora.TalkID
    INNER JOIN segSUW ON
                relMora2SUW.SUWID = segSUW.SUWID AND
                relMora2SUW.MoraID = segMora.MoraID AND
                relMora2SUW.TalkID = segSUW.TalkID AND
                relMora2SUW.TalkID = segMora.TalkID
    INNER JOIN segIPU ON
                relMora2IPU.IPUID = segIPU.IPUID AND
                relMora2IPU.MoraID = segMora.MoraID AND
                relMora2IPU.TalkID = segIPU.TalkID AND
                relMora2IPU.TalkID = segMora.TalkID
    INNER JOIN MoraPhones ON MoraPhones.MoraPhoneID = segMora.MoraID
    INNER JOIN infoTalk ON segPhone.TalkID = infoTalk.TalkID
    INNER JOIN infoSpeaker ON infoTalk.SpeakerID = infoSpeaker.SpeakerID
    
    /*Subquery for getting following mora*/
    LEFT JOIN (
        /*Make a table of moras mapped to their APs*/
        SELECT
            FollMoras.MoraEntity AS FolMora,
            FollMoras.MoraID AS FolMoraID,
            APMoraRef.APID AS APRefID, APMoraRef.nth AS APRefNth,
            APMoraRef.TalkID AS APRefTalk
        FROM segMora AS FollMoras, relMora2AP AS APMoraRef
        INNER JOIN segAP AS APMora ON
            APMora.APID = APMoraRef.APID AND
            FollMoras.MoraID = APMoraRef.MoraID AND
            APMora.TalkID = APMoraRef.TalkID AND
            FollMoras.TalkID = APMoraRef.TalkID

    /*Add these table columns for the next
      mora in the AP*/
    ) ON
        APRefID = relMora2AP.APID AND
        APRefTalk = relMora2AP.TalkID AND
        APRefNth = (relMora2AP.nth + 1)

    WHERE
        /*Conditions: only get vowels*/
        (segPhoneme.PhonemeEntity = "a" OR segPhoneme.PhonemeEntity = "e" OR
        segPhoneme.PhonemeEntity = "i" OR segPhoneme.PhonemeEntity = "o" OR
        segPhoneme.PhonemeEntity = "u") AND
        /*Moras with at least two phonemes*/
        relPhoneme2Mora.len = 2;
