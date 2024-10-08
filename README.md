> [!WARNING]  
> This script is for test tenants only. Do not run this in a production Farm as it will set departments for all users randomly, create an Exchange Address Book policy for all users, then enable IB based the defiend departments.

> [!TIP]
> The script will ask you for your Tenant name and if you want "Allow" or "Block" Policies.
>
> Example:
>
> What is your tenant name? IE: M365x03708457: **M365x65798550**
>
> Do you want Allow or Block Policies?
> 
> Please enter 'allow' or 'block': **block**

> [!TIP]
> After that, the script will create 3 departments "HR", "Sales" and "Research". This is configurable by modifying the script.
> Each Department will be an IB Segment.
>
> If you choose "Allow" policies: HR will allow sales and Research. Research will allow HR and Sales will allow HR.
>
> If you choose "Block" policies: Sales will block Research and Research will block Sales.
>

Example:

![image](https://github.com/user-attachments/assets/c6c1bb95-3053-45ba-8475-75e2bab38b07)


**Here is a list of takes completed by the script:**

1. Prompts the user for the tenant name and the type of policies (Allow or Block).
2. Connects to various Office 365 services including Exchange Online, SharePoint Online, and IPPS.
3. Enables Organization Customizations
4. Creates an Address Book Policy to prevent an empty address book.
5. Assigns the new Address Book Policy to all mailboxes.
6. Applies department attributes to users.
7. Creates organization segments based on departments.
8. Creates Information Barrier Policies based on the selected policy type (Allow or Block).
9. Starts the application of Information Barrier Policies.
10. Enables Information Barriers for SharePoint and OneDrive.
11. Triggers Personal Site creations using "Request-SPOPersonalSite" for all users.
12. Updates existing OneDrive sites with segments.
13. Checks the current state of Information Barriers and retrieves various IB settings.
14. Checks IB compatibility between random users.
15. Retrieves IB settings for users, OneDrive sites, and SharePoint sites.



> [!TIP]
>To learn more about using Information Barriers with SharePoint see the following article.
> https://learn.microsoft.com/en-us/purview/information-barriers-sharepoint
