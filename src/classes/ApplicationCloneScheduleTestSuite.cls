/**
 * Created by maxim_elets on 10/14/19.
 */

@IsTest
private with sharing class ApplicationCloneScheduleTestSuite {

	@IsTest
	private static void testBatch() {
		Profile profile = [select id, Name from profile where name='System Administrator'];
		User u1 = new User(Alias = 'tt01', Email='testtest01@test.com', EmailEncodingKey='UTF-8', LastName='testtest01', LanguageLocaleKey='en_US',
				LocaleSidKey='en_US', ProfileId = profile.Id, TimeZoneSidKey='America/Los_Angeles', Username='testtest01@test343SF111112d.com',
				UserType__c = 'Counselor'
		);
		Database.insert(u1);
		System.runAs(u1) {
			Contact counselorContact = new Contact(LastName='Counselor',User__c = u1.Id);
			insert counselorContact;
			System.Test.startTest();

			Application__c app = new Application__c(
					Contact__c = [SELECT Id FROM Contact WHERE LastName = 'TestStudent'].Id,
					Application_Status__c = 'Started',
					Intended_Term_of_Entry__c = [SELECT Id FROM Academic_Term__c WHERE Name = 'current'].Id
			);
			insert app;
			List<Application__c> appsToProceed = [SELECT Id FROM Application__c
				WHERE Intended_Term_of_Entry__r.Term_Census_Date__c <= YESTERDAY
					AND Application_Status__c NOT IN ('Withdrawn', 'Historic', 'Cancelled')
			];
			System.assertEquals(1, [SELECT Id FROM Application__c].size(), '1 to go');
			ApplicationCloneSchedule b = new ApplicationCloneSchedule();
			Database.executeBatch(b);
			System.Test.stopTest();
			System.assertEquals(2, [SELECT Id FROM Application__c].size(), '2 apps created, one historic 2nd real one');
		}
	}

	@TestSetup
	private static void setupData() {
		Application_Control__c appControl = new Application_Control__c(
				Application_Start_Status__c=Application_Control__c.Application_Start_Status__c.getDescribe().getPicklistValues()[0].getValue(),
				Active__c=true,
				Allow_Cancel_From__c=Application_Control__c.Allow_Cancel_From__c.getDescribe().getPicklistValues()[0].getValue(),
				Allow_Withdraw_From__c=Application_Control__c.Allow_Withdraw_From__c.getDescribe().getPicklistValues()[0].getValue(),
				Allow_Submit_From__c=Application_Control__c.Allow_Submit_From__c.getDescribe().getPicklistValues()[0].getValue(),
				Cancel_Status__c=Application_Control__c.Cancel_Status__c.getDescribe().getPicklistValues()[0].getValue(),
				Default__c=true,
				URL_Parameter__c ='st',
				Submit_Status__c=Application_Control__c.Submit_Status__c.getDescribe().getPicklistValues()[0].getValue(),
				Withdraw_Status__c=Application_Control__c.Withdraw_Status__c.getDescribe().getPicklistValues()[0].getValue()
		);
		insert appControl;
		Account studAccount = new Account(Name = 'Student');
		insert studAccount;
		Contact student = new Contact(LastName='TestStudent', AccountId = studAccount.Id);
		insert student;
		Academic_Term__c at = new Academic_Term__c(Name = 'current', Term_Start_Date__c = Date.TODAY().addDays(-150),
				Activate_Application_Date__c = Date.TODAY().addDays(-200), End_Application_Date__c = Date.TODAY().addDays(-100));
		insert at;
		Academic_Term__c at2 = new Academic_Term__c(Name = 'next', Term_Start_Date__c = Date.TODAY().addDays(40), Activate_Application_Date__c = Date.TODAY().addDays(30), End_Application_Date__c = Date.TODAY().addDays(50));
		insert at2;
	}
}