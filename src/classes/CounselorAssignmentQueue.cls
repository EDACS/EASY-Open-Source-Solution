/**
 * Created by maxim_elets on 2019-09-02.
 */

public without sharing class CounselorAssignmentQueue {

	public static Boolean RUN_AS_TEST = false; //to cover code
	private static String COUNSELOR_TYPE = 'Counselor';
	private static String COUNSELOR_FORMER_STATUS = 'Former';
	private static String COUNSELOR_CURRENT_STATUS = 'Current';
	private static String RELATIONSHIP_DESCRIPTION_FORMAT = '\\r\\n Automated counselor assignment process: {0}';
	private static String OPPORTUNITY_APPLICANT_RECORD_TYPE = Opportunity.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get('Applicant_Opportunity').recordTypeId;

	@InvocableMethod(label='(ONU-215-WIP)Assign Counselor To Record' description='(ONU-215-WIP)')
	public static void proceedRequests(Request[] requests) {
		if ( (!System.Test.isRunningTest() || RUN_AS_TEST) &&  requests != NULL && !requests.isEmpty()) {
			updateCounselorOnContactAndRelatedRecords(requests[0].recordId);
		}
	}

	public static void updateCounselorOnContactAndRelatedRecords(Id p_applicationId) {

		List<Application__c> applications = [
				SELECT Id, Name, Contact__c, Intended_Program__c, Intended_Term_of_Entry__c,
						Intended_Program__r.Name,Intended_Program__r.Program_Code__c, Intended_Term_of_Entry__r.Name,
						Intended_Term_of_Entry__r.Term__c
				FROM Application__c WHERE Id =:p_applicationId];

		if (!applications.isEmpty()) {
			Application__c application =applications[0];
			List<Contact> contacts  = [SELECT Id, Name, FirstName, LastName, Counselor__c, Counselor__r.IsActive,
					AccountId, Account.Counselor__c, Account.Counselor__r.IsActive
			FROM Contact WHERE Id = :application.Contact__c LIMIT 1];

			if (!contacts.isEmpty()) {
				Contact studentContact = contacts[0];
				Boolean contactCounselorIsNotActive = studentContact.Counselor__c == NULL || !studentContact.Counselor__r.IsActive;
				Boolean accountCounselorIsNotActive = studentContact.Account.Counselor__c == NULL || !studentContact.Account.Counselor__r.IsActive;
				if (contactCounselorIsNotActive) {
					Contact counselorContact;
					if (accountCounselorIsNotActive) {
						//assign new counselor
						counselorContact = balancedCounselorQueue();
					} else {
						List<Contact> accountCounselorContacts = [SELECT Id, User__c FROM Contact WHERE User__c = :studentContact.Account.Counselor__c LIMIT 1];
						//if there is no contacts, we have to assign new contact/user/counselor
						if (accountCounselorContacts.isEmpty()) {
							counselorContact = balancedCounselorQueue();
						} else {
							counselorContact = accountCounselorContacts[0];
						}

					}


					deactivateRelationships(studentContact.Id);
					activateNewCounselorRelationships(studentContact.Id, counselorContact.Id);

					deactivateAffiliations(studentContact.Id, studentContact.AccountId, counselorContact.Id);
					activateNewCounselorAffiliations(studentContact.Id, studentContact.AccountId, counselorContact.Id);

					setOwnerForApplications(p_applicationId, counselorContact.User__c);
					setOwnerForInteractions(studentContact, counselorContact.User__c, application);
					setOwnerForOpportunities(studentContact, counselorContact.User__c, application);

					setCounselorContactsAssigned(counselorContact.User__c);


					setContactCounselor(studentContact.Id, counselorContact.User__c);
					if (accountCounselorIsNotActive) {
						setAccountCounselor(studentContact.AccountId, counselorContact.User__c);
					}
				}
			}
		}
	}

	private static void setContactCounselor(Id p_studentContactId, Id p_counselorUserId) {
		System.debug('>>>>>>> setContactCounselor - START');
		Database.update(new Contact(Id = p_studentContactId, Counselor__c = p_counselorUserId));
		System.debug('>>>>>>> setContactCounselor - END');
	}
	private static void setAccountCounselor(Id p_accountId, Id p_counselorUserId) {
		System.debug('>>>>>>> setAccountCounselor - START');
		Database.update(new Account(Id = p_accountId, Counselor__c = p_counselorUserId));
		System.debug('>>>>>>> setAccountCounselor - END');
	}

	private static void deactivateRelationships(Id p_studentContactId) {
		System.debug('>>>>>>> deactivateRelationships - START');
		// RELATIONSHIP RECORDS - set old relationship to ended
		List<hed__Relationship__c> counselorRelationships = [
				SELECT Id, hed__Status__c, hed__Description__c, End_Date__c
				FROM hed__Relationship__c
				WHERE hed__Contact__c = :p_studentContactId
				AND hed__Type__c = :COUNSELOR_TYPE
		];
		for (hed__Relationship__c rel : counselorRelationships) {
			rel.hed__Status__c = COUNSELOR_FORMER_STATUS;
			rel.hed__Description__c += String.format(RELATIONSHIP_DESCRIPTION_FORMAT, new List<String> {
					'Counselor is not active.'
			});
			rel.End_Date__c = System.today();
		}
		Database.update(counselorRelationships);
		System.debug('>>>>>>> deactivateRelationships - END');
	}
	private static void activateNewCounselorRelationships(Id p_studentContactId, Id p_counselorId) {
		System.debug('>>>>>>> activateNewCounselorRelationships - START');
		// RELATIONSHIP RECORDS
		Database.insert(new hed__Relationship__c(
				hed__Contact__c = p_studentContactId,
				hed__RelatedContact__c = p_counselorId,
				hed__Status__c = COUNSELOR_CURRENT_STATUS,
				hed__Description__c = String.format(RELATIONSHIP_DESCRIPTION_FORMAT, new List<String> {
						'New Counselor assigned.'
				}),
				Start_Date__c = System.today(),
				hed__Type__c = COUNSELOR_TYPE
		));
		System.debug('>>>>>>> activateNewCounselorRelationships - END');
	}

	private static void deactivateAffiliations(Id p_studentContactId, Id p_studentAccountId, Id p_counselorId) {
		System.debug('>>>>>>> deactivateAffiliations - START');
		//AFFILIATIONS RECORDS
		List<hed__Affiliation__c> counselorAffiliations = [
				SELECT Id, hed__EndDate__c, hed__Status__c, hed__Description__c
				FROM hed__Affiliation__c
				WHERE hed__Contact__c = :p_counselorId
				AND hed__Role__c =:COUNSELOR_TYPE
		];
		for (hed__Affiliation__c rel : counselorAffiliations) {
			rel.hed__Status__c = COUNSELOR_FORMER_STATUS;
			rel.hed__Description__c += String.format(RELATIONSHIP_DESCRIPTION_FORMAT, new List<String> {
					'Counselor is not active.'
			});
			rel.hed__EndDate__c = System.today();
		}
		Database.update(counselorAffiliations);

		System.debug('>>>>>>> deactivateAffiliations - END');
	}
	private static void activateNewCounselorAffiliations(Id p_studentContactId, Id p_studentAccountId, Id p_counselorId) {
		System.debug('>>>>>>> activateNewCounselorAffiliations - START');
		//AFFILIATIONS RECORDS
		Database.insert(new hed__Affiliation__c(hed__Contact__c = p_counselorId,
				hed__Account__c = p_studentAccountId,
				hed__Status__c = COUNSELOR_CURRENT_STATUS,
				hed__Description__c = String.format(RELATIONSHIP_DESCRIPTION_FORMAT, new List<String> {
						'New Counselor assigned.'
				}),
				hed__StartDate__c = System.today(),
				hed__Role__c = COUNSELOR_TYPE
		));
		System.debug('>>>>>>> activateNewCounselorAffiliations - END');
	}

	private static void setOwnerForApplications(Id p_applicationId, Id p_counselorUserId) {
		System.debug('>>>>>>> setOwnerForApplications - START');
		//APPLICATIONS
		List<Application__c> applications = [SELECT Id, OwnerId FROM Application__c WHERE Id = :p_applicationId AND OwnerId != :p_counselorUserId];
		System.debug('>>>>>>> setOwnerForApplications - ' + applications.size());
		System.debug('>>>>>>> setOwnerForApplications - ' + p_counselorUserId);
		for (Application__c app : applications) {
			app.OwnerId = p_counselorUserId;
		}
		Database.update(applications);
		System.debug('>>>>>>> setOwnerForApplications - END');
	}
	private static void setOwnerForOpportunities(Contact p_studentContact, Id p_counselorUserId, Application__c p_application) {
		System.debug('>>>>>>> setOwnerForOpportunities - START');
		//OPPORTUNITY
		List<Opportunity> opportunities = [SELECT Id, Name, LeadSource, OwnerId FROM Opportunity WHERE Contact__c = :p_studentContact.Id AND OwnerId != :p_counselorUserId];
		for (Opportunity rel : opportunities) {
			rel.OwnerId = p_counselorUserId;
			rel.Name = String.format('{0} {1} {2}', new List<String>{
					p_studentContact.LastName,
					String.isBlank(p_application.Intended_Program__r.Program_Code__c) ? p_application.Intended_Program__r.Name : p_application.Intended_Program__r.Program_Code__c,
					p_application.Intended_Term_of_Entry__r.Name
			});
			rel.LeadSource = 'Application';
			//TODO: status update??;
		}
		Database.update(opportunities);

		if (opportunities.isEmpty()) {

			Database.insert(new Opportunity(Contact__c = p_studentContact.Id,
					OwnerId = p_counselorUserId,
					RecordTypeId = OPPORTUNITY_APPLICANT_RECORD_TYPE,
					Name = String.format('{0} {1} {2}', new List<String>{
							p_studentContact.LastName,
							String.isBlank(p_application.Intended_Program__r.Program_Code__c) ? p_application.Intended_Program__r.Name : p_application.Intended_Program__r.Program_Code__c,
							p_application.Intended_Term_of_Entry__r.Name
					}),
					AccountId = p_studentContact.AccountId,
					StageName = 'Applied',
					CloseDate = System.today(),
	//					Application_Number__c = application.Name,
					Academic_Program__c = p_application.Intended_Program__c,
					Academic_Term__c = p_application.Intended_Term_of_Entry__c,
					LeadSource = 'Application'

			));
		}

		System.debug('>>>>>>> setOwnerForOpportunities - END');

	}
	private static void setOwnerForInteractions(Contact p_studentContact, Id p_counselorUserId, Application__c p_application) {
		System.debug('>>>>>>> setOwnerForInteractions - START');
		//OPPORTUNITY
		List<Interaction__c> interactions = [SELECT Id, Academic_Term__r.Term__c, Term__c, OwnerId FROM Interaction__c WHERE Contact__c = :p_studentContact.Id AND OwnerId != :p_counselorUserId];
		for (Interaction__c rel : interactions) {
			rel.OwnerId = p_counselorUserId;
			System.debug('>>>>>>> Term - ' + p_application.Intended_Term_of_Entry__r.Term__c);
//			rel.Term__c = p_application.Intended_Term_of_Entry__r.Term__c;
		}
		Database.update(interactions);
		System.debug('>>>>>>> setOwnerForInteractions - END');

	}

	private  static Contact balancedCounselorQueue() {
		System.debug('>>>>>>> balancedCounselorQueue - START');
		List<Contact> counselors = [
				SELECT Id, Name, User__c
				FROM Contact
				WHERE User__c != NULL
				AND User__r.IsActive = TRUE
				AND User__r.UserType__c = :COUNSELOR_TYPE
				ORDER BY User__r.ContactsAssigned__c ASC
				LIMIT 1
		];
		if (counselors.isEmpty()) {
			throw new CounselorAssignmentQueueException('No Counselor Contact Records Found');
		}
		System.debug('>>>>>>> balancedCounselorQueue - END');
		return counselors[0];
	}

	private static void setCounselorContactsAssigned(Id p_counselorUserId) {
		System.debug('>>>>>>> setCounselorContactsAssigned - START');
		System.debug('>>>>>>> setCounselorContactsAssigned - ' + p_counselorUserId);
		User counselorUser = [SELECT Id, ContactsAssigned__c FROM User WHERE Id = :p_counselorUserId];
		System.debug('>>>>>>> setCounselorContactsAssigned - ' + counselorUser);
		if (counselorUser.ContactsAssigned__c == NULL) {
			counselorUser.ContactsAssigned__c = 1;
		} else {
			counselorUser.ContactsAssigned__c++;
		}
		  
		Database.update(counselorUser);
		System.debug('>>>>>>> setCounselorContactsAssigned - END');
	}
	public class CounselorAssignmentQueueException extends Exception {}

	public with sharing class Request {
		@InvocableVariable(label='Record ID(Application)' required=true)
		public Id recordId;
	}
}