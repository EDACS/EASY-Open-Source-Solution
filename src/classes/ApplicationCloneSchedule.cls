/**
 * Created by maxim_elets on 9/24/19.
 * ONU-222;
 */

public with sharing class ApplicationCloneSchedule implements Database.Batchable<sObject>,
                                                                Schedulable,
                                                                Database.Stateful {

//  ApplicationCloneSchedule b = new ApplicationCloneSchedule();
//  String sch = '0 0 1 * * ?'; // This is just like a regular cron job
//  system.schedule('Application Clone(ONU-222)', sch, b);
    public void execute(SchedulableContext param1) {
        ApplicationCloneSchedule b = new ApplicationCloneSchedule();
        Database.executeBatch(b);
    }

    private Set<String> APPLICATION_IGNORE_STATUSES = new Set<String> {
            'Withdrawn', 'Historic', 'Cancelled'
    };
    private String query;
    private Map<Id, Academic_Term__c> priorNextAcademicTermsIds;//what is next term for key Id
    private Map<Id, Academic_Term__c> academicTermsMap; // id  + their record
    public ApplicationCloneSchedule() {
        List<Schema.SObjectField> applicationFields = getAllFields(Application__c.SObjectType);
        List<String> applicationFieldsAsStrings = new List<String>();
        for (Schema.SObjectField f : applicationFields) {
            applicationFieldsAsStrings.add(f.getDescribe().getLocalName());
        }
        List<Schema.SObjectField> opportunityFields = getAllFields(Opportunity.SObjectType);
        List<String> opportunityFieldsAsStrings = new List<String>();
        for (Schema.SObjectField f : opportunityFields) {
            opportunityFieldsAsStrings.add('Opportunity__r.' + f.getDescribe().getLocalName());
        }

        String q = String.format('SELECT {0}, {1}, {3} FROM Application__c WHERE Intended_Term_of_Entry__r.Term_Census_Date__c <= {2} AND Application_Status__c NOT IN :APPLICATION_IGNORE_STATUSES',
                new List<String> {
                        String.join(applicationFieldsAsStrings, ','),
                        String.join(opportunityFieldsAsStrings, ','),
                        'YESTERDAY', //'2019-09-12'
                        String.join(new List<String> {
                                'Intended_Term_of_Entry__r.Term_Census_Date__c',
                                'Opportunity__r.Contact__r.LastName',
                                'Opportunity__r.Academic_Program__r.Program_Code__c',
                                'Opportunity__r.Academic_Program__r.Name'
                        }, ',')//reuiqred fields
                });
        System.debug(q);
        this.query = q;


        //populate academic term order;
        this.priorNextAcademicTermsIds = new Map<Id, Academic_Term__c>();

        List<Academic_Term__c> terms  = [SELECT Id, Name FROM Academic_Term__c WHERE Term_Start_Date__c != NULL ORDER BY Term_Start_Date__c ASC];
        this.academicTermsMap = new Map<Id, Academic_Term__c>(terms);
        Integer iterations = terms.size()-1;
        while (iterations >= 0) {
            Academic_Term__c currentAt = terms.get(iterations);
            if (iterations == terms.size()-1) { //last added term
                this.priorNextAcademicTermsIds.put(currentAt.Id, NULL);
            } else {
                Academic_Term__c nextAt = terms.get(iterations + 1);
                this.priorNextAcademicTermsIds.put(currentAt.Id, nextAt);
            }
            iterations--;
        }
        System.debug(this.priorNextAcademicTermsIds);
    }
    private Boolean onlyClone = false;
    private String cloneComment = '';
    public ApplicationCloneSchedule(String p_query, String p_cloneComment) {
        this.query = p_query;
        this.onlyClone = true;
        this.cloneComment = p_cloneComment;
    }
    public Iterable<sObject> start(Database.BatchableContext ctx) {
        System.debug(this.query);
        return Database.getQueryLocator(this.query);
    }
    public void execute(Database.BatchableContext ctx, List<sObject> scope) {
        Savepoint sp = Database.setSavepoint();
        try {
            System.debug(scope.size());
            List<Application__c> snapshots = new List<Application__c>();
            Map<Id, Application__c> originalApplicationsMap = new Map<Id, Application__c>((List<Application__c>)scope);
            Map<Id, Opportunity> originalOpportunitiesMap = new Map<Id, Opportunity>();//to close
            Map<Id, Integer> cloneCounterMap = new Map<Id, Integer>();
            for (Application__c oa : (List<Application__c>)scope) {
                Integer nextCloneCount = Integer.valueOf(oa.Clone_Count__c != NULL ? (oa.Clone_Count__c + 1) : 1);
                if (nextCloneCount > 2) {
                    oa.Application_Status__c = 'Cancelled';
                } else {
                    //SNAPSHOTS
                    Application__c ha = oa.clone(false, true, false, false);
                    ha.Application_Status__c = 'Historic';
                    ha.OriginalApplication__c = oa.Id;

                    snapshots.add(ha);

                    //ORIGINAL
                    if ( !this.onlyClone && this.priorNextAcademicTermsIds.containsKey(oa.Intended_Term_of_Entry__c)) {
                        oa.Intended_Term_of_Entry__c = this.priorNextAcademicTermsIds.get(oa.Intended_Term_of_Entry__c).Id;
                        if (oa.Intended_Term_of_Entry__c == NULL) {
                            throw new ApplicationCloneScheduleException('Next academic term is not available for record: ' + oa.Id);
                        }
                    }
                    oa.Clone_Count__c = nextCloneCount;
                    oa.Clone_Comment__c = String.isNotBlank(oa.Clone_Comment__c) ? oa.Clone_Comment__c : '';
                    if (String.isBlank(this.cloneComment)) {
                        oa.Clone_Comment__c += '\r\nHISTORY APPLICATION CREATED: Term Census Date = ' + oa.Intended_Term_of_Entry__r.Term_Census_Date__c;
                    } else {
                        oa.Clone_Comment__c = this.cloneComment + '\r\n' + oa.Clone_Comment__c;
                    }

                    if (oa.Opportunity__r != NULL) {
                        originalOpportunitiesMap.put(oa.Opportunity__c, oa.Opportunity__r);
                        cloneCounterMap.put(oa.Opportunity__c, Integer.valueOf(oa.Clone_Count__c));
                    }

                }
            }
            //insert new opportunities
            Map<Id, Opportunity> historicalOpportunitiesMap = new Map<Id, Opportunity>(); // to insert
            for (Opportunity oo : originalOpportunitiesMap.values()) {
                System.debug(oo.Academic_Term__c);
                System.debug(this.priorNextAcademicTermsIds);
                if (!this.onlyClone) {
                    oo.Academic_Term__c = this.priorNextAcademicTermsIds.get(oo.Academic_Term__c).Id;
                    oo.Name = String.format('{0} {1} {2} {}', new List<String>{
                            oo.Contact__r.LastName,
                            String.isBlank(oo.Academic_Program__r.Program_Code__c) ? oo.Academic_Program__r.Name : oo.Academic_Program__r.Program_Code__c,
                            this.academicTermsMap.get(oo.Academic_Term__c).Name
                    }
                    );
                }
                oo.Status_picklist__c = 'Open';
                if (oo.Amount != NULL) {
                    oo.Amount = oo.Amount - (oo.Amount*33/100);// TODO: based on clone count;
                }


                //open new opportunity
                Opportunity ho = oo.clone(false, true, false, false);
                //close old opportunity
                ho.Status_picklist__c = 'Lost';
                ho.Status_Reason__c = 'Rolled';
                ho.OriginalOpportunity__c = oo.Id;
                ho.Opportunity_Key__c = NULL;
                ho.Name += 'Historic_' + cloneCounterMap.get(oo.Id);
                historicalOpportunitiesMap.put(oo.Id, ho);
                System.debug(ho.Id);
            }
            //update original opportunities
            Database.update(originalOpportunitiesMap.values());
            //insert historical opportunities
            Database.insert(historicalOpportunitiesMap.values());

            //update opportunity on historical applicaitons
            for (Application__c ha : snapshots) {
                if (historicalOpportunitiesMap.containsKey(ha.Opportunity__c)) {
                    ha.Opportunity__c = historicalOpportunitiesMap.get(ha.Opportunity__c).Id;
                } else {

                }

            }
            //insert historical applications
            Database.insert(snapshots);

            //update original applications
            Database.update(scope);
        } catch (Exception e) {
            Database.rollback(sp);
            throw new ApplicationCloneScheduleException(e.getMessage() + ' - ' + e.getStackTraceString());
        }
    }

    public void finish(Database.BatchableContext ctx) {
    }


    /**
    * @description Get all fields of a SObject.
    * @param p_sobjectType Schema.SObjectType of a SObject tgetAllFieldso get writable fields.
    * @return List of Schema.SObjectField writable fields.
    */
    public static final Set<String> FIELDS_TO_IGNORE = new Set<String> {
            'LastViewedDate', 'LastReferencedDate', 'LastActivityDate', 'IqScore' };
    private static List<Schema.SObjectField> getAllFields(Schema.SObjectType p_sobjectType) {

        return SchemaUtils.getAllFields(p_sobjectType, FIELDS_TO_IGNORE);
    }

    public class ApplicationCloneScheduleException extends Exception { }

}