<?xml version="1.0" encoding="UTF-8"?>
<Workflow xmlns="http://soap.sforce.com/2006/04/metadata">
    <alerts>
        <fullName>Send_SMS_check_in_email</fullName>
        <description>Send SMS check in email</description>
        <protected>false</protected>
        <recipients>
            <field>Email</field>
            <type>email</type>
        </recipients>
        <senderType>CurrentUser</senderType>
        <template>unfiled$public/Check_In_To_Event</template>
    </alerts>
    <fieldUpdates>
        <fullName>Campaign_Member_Key_Update_to_Lead_Camp</fullName>
        <description>Sets the Campaign Member Key field to LeadId.CampaignId</description>
        <field>Campaign_Member_Key__c</field>
        <formula>LeadId&amp;&quot;.&quot;&amp;CampaignId</formula>
        <name>Campaign Member Key: Update to Lead.Camp</name>
        <notifyAssignee>false</notifyAssignee>
        <operation>Formula</operation>
        <protected>false</protected>
    </fieldUpdates>
    <rules>
        <fullName>Campaign Member%3A Update Campaign Member Key for Lead</fullName>
        <actions>
            <name>Campaign_Member_Key_Update_to_Lead_Camp</name>
            <type>FieldUpdate</type>
        </actions>
        <active>true</active>
        <description>Runs on any update of Campaign Member associated to a Lead if the key is not Lead.Campaign</description>
        <formula>NOT(ISBLANK(LeadId)) &amp;&amp; Campaign_Member_Key__c &lt;&gt; LeadId&amp;&quot;.&quot;&amp;CampaignId</formula>
        <triggerType>onAllChanges</triggerType>
    </rules>
    <rules>
        <fullName>Send check in email</fullName>
        <actions>
            <name>Send_SMS_check_in_email</name>
            <type>Alert</type>
        </actions>
        <active>false</active>
        <criteriaItems>
            <field>CampaignMember.Status</field>
            <operation>equals</operation>
            <value>SMS Sent</value>
        </criteriaItems>
        <triggerType>onCreateOrTriggeringUpdate</triggerType>
    </rules>
</Workflow>
