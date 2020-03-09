/**
 * Created by maxim_elets on 10/23/19.
 */

public with sharing class ApplicationCloneController {
	public Id applicationId {get; set; }
	public Application__c application { get; set; }
	public Boolean cloneNotAvailable { get; set; }
	public String cloneComment { get; set; }
	public Boolean cloneInProgress { get; set; }
	public ApplicationCloneController(ApexPages.StandardController std) {
		this.applicationId = std.getId();
		this.cloneNotAvailable = false;
		this.cloneComment = '';
		this.cloneInProgress = this.checkIfCloneInProgress();

		List<Application__c> applications = Database.query(this.getApplicationQuery());
		if (applications.size() > 0) {
			this.application = applications.get(0);
		} else {
			this.cloneNotAvailable = true;
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR,
					'\'Withdrawn\', \'Historic\', \'Cancelled\' applications can\'t be cloned. Also application can be cloned only 2 times.'));
		}
	}

	public Boolean getHasMessages() {
		return  ApexPages.hasMessages();
	}

	public Boolean getHasErrorMessages() {
		return  ApexPages.hasMessages(ApexPages.Severity.ERROR);
	}

	public void doClone() {
		if (this.checkIfCloneInProgress()) {
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR,
					'There is another clone process was not finished yet. Please try again soon, or please check clone process status in Setup->Apex Jobs'));
			System.debug('JOB');
		} else {
			ApplicationCloneSchedule b = new ApplicationCloneSchedule(this.getApplicationQuery(), String.isNotBlank(this.cloneComment) ? this.cloneComment : 'Manually Cloned by ' + UserInfo.getName());
			Id jobId = Database.executeBatch(b);
			this.setCookie(jobId);
			this.cloneInProgress = true;
		}
	}
	@TestVisible
	private Boolean checkIfCloneInProgress() {
		Set<String> completedStatuses = new Set<String> {
				'Completed', 'Failed'
		};
		Id jobId = this.getCurrentCronIdFromCookie();
		if (jobId != NULL) {
			AsyncApexJob aaj = this.getApexJobStatusById(jobId);
			return !completedStatuses.contains(aaj.Status);
		}

		return false;
	}
	private Set<String> APPLICATION_IGNORE_STATUSES = new Set<String> {
			'Withdrawn', 'Historic', 'Cancelled'
	};
	private String getApplicationQuery() {
		List<Schema.SObjectField> applicationFields = SchemaUtils.getAllFields(Application__c.SObjectType, NULL);
		List<String> applicationFieldsAsStrings = new List<String>();
		for (Schema.SObjectField f : applicationFields) {
			applicationFieldsAsStrings.add(f.getDescribe().getLocalName());
		}
		List<Schema.SObjectField> opportunityFields = SchemaUtils.getAllFields(Opportunity.SObjectType, NULL);
		List<String> opportunityFieldsAsStrings = new List<String>();
		for (Schema.SObjectField f : opportunityFields) {
			opportunityFieldsAsStrings.add('Opportunity__r.' + f.getDescribe().getLocalName());
		}

		String q = String.format('SELECT {0}, {1}, {3} FROM Application__c WHERE Id = {2} AND Application_Status__c NOT IN :APPLICATION_IGNORE_STATUSES AND (Clone_Count__c = NULL OR Clone_Count__c < 2)',
				new List<String> {
						String.join(applicationFieldsAsStrings, ','),
						String.join(opportunityFieldsAsStrings, ','),
						'\''+ this.applicationId + '\'', //'2019-09-12'
						String.join(new List<String> {
								'Intended_Term_of_Entry__r.Term_Census_Date__c',
								'Opportunity__r.Contact__r.LastName',
								'Opportunity__r.Academic_Program__r.Program_Code__c',
								'Opportunity__r.Academic_Program__r.Name'
						}, ',')//reuiqred fields
				});
		System.debug(q);
		return q;
	}


	private Id getCurrentCronIdFromCookie() {
		Cookie cookieMap = ApexPages.currentPage().getCookies().get('application_clone_map');
		if (cookieMap != NULL) {
			Map<Id, Id> data = (Map<Id, Id>)JSON.deserialize(cookieMap.getValue(), Map<Id, Id>.class);
			if (data.containsKey(this.applicationId)) {
				return data.get(this.applicationId);
			}
		}
		return NULL;
	}
	private void setCookie(Id p_jobId) {
		Cookie cookieMap = ApexPages.currentPage().getCookies().get('application_clone_map');
		Map<Id, Id> data;
		if (cookieMap == NULL) {
			data = new Map<Id, Id>();
			data.put(this.applicationId, p_jobId);
		} else {
			// If this isn't the first time the user is accessing the page
			// create a new cookie, incrementing the value of the original count by 1
			data = (Map<Id, Id>)JSON.deserialize(cookieMap.getValue(), Map<Id, Id>.class);
			data.put(this.applicationId, p_jobId);
		}
		cookieMap = new Cookie('application_clone_map', JSON.serialize(data),NULL,-1,false);

		// Set the new cookie for the page
		ApexPages.currentPage().setCookies(new Cookie[]{ cookieMap });
	}

	private AsyncApexJob getApexJobStatusById(Id p_jobId) {
		return [SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors FROM AsyncApexJob WHERE Id =: p_jobId ];
	}
}