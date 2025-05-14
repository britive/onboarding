import os

import oci
from britive.britive import Britive
from colorama import Fore, Style

# Color definitions from Colorama
caution: str = f"{Style.BRIGHT}{Fore.RED}"
warn: str = f"{Style.BRIGHT}{Fore.YELLOW}"
info: str = f"{Style.BRIGHT}{Fore.BLUE}"
green: str = f"{Style.BRIGHT}{Fore.GREEN}"

# Instance Britive
br = Britive(tenant=os.getenv("BRITIVE_TENANT"), token=os.getenv("BRITIVE_API_TOKEN"))


class OCIInt:
    def __init__(self, config_file):
        # Load OCI configuration file
        self.config = oci.config.from_file(config_file)
        self.identity_client = oci.identity.IdentityClient(self.config)
        self.tenancy_ocid = self.config["tenancy"]

    def get_tenancy_ocid(self):
        """
        Get the OCID of the root compartment (tenancy).
        """
        print(f"Tenancy OCID: {self.tenancy_ocid}")
        return self.tenancy_ocid

    def create_user(self, first_name, last_name, email):
        """
        Create a user in the root compartment (tenancy).
        """
        create_user_details = oci.identity.models.CreateUserDetails(
            compartment_id=self.tenancy_ocid,
            name=email.split("@")[0],  # Use email as base for the name
            description=f"User {first_name} {last_name}",
            email=email,
        )
        user = self.identity_client.create_user(create_user_details).data
        print(f"User Created: {user.name}, OCID: {user.id}")
        return user

    def add_api_key_to_user(self, user_id, public_key_content):
        """
        Add an API key to a user.
        """
        api_key_details = oci.identity.models.CreateApiKeyDetails(
            key=public_key_content
        )
        api_key = self.identity_client.upload_api_key(user_id, api_key_details).data
        print(f"API Key Fingerprint: {api_key.fingerprint}")
        return api_key

    def create_group(self, group_name, description):
        """
        Create a group in the root compartment (tenancy).
        """
        create_group_details = oci.identity.models.CreateGroupDetails(
            compartment_id=self.tenancy_ocid, name=group_name, description=description
        )
        group = self.identity_client.create_group(create_group_details).data
        print(f"Group Created: {group.name}, OCID: {group.id}")
        return group

    def assign_user_to_group(self, user_id, group_id):
        """
        Assign a user to a group.
        """
        add_user_group_details = oci.identity.models.AddUserToGroupDetails(
            user_id=user_id, group_id=group_id
        )
        self.identity_client.add_user_to_group(add_user_group_details)
        print(f"User with OCID {user_id} added to group with OCID {group_id}")

    def create_policy(self, policy_name, policy_statements, description):
        """
        Create a policy in the root compartment (tenancy).
        """
        create_policy_details = oci.identity.models.CreatePolicyDetails(
            compartment_id=self.tenancy_ocid,
            name=policy_name,
            description=description,
            statements=policy_statements,
        )
        policy = self.identity_client.create_policy(create_policy_details).data
        print(f"Policy Created: {policy.name}, OCID: {policy.id}")
        return policy


# Example Usage
if __name__ == "__main__":
    oci_manager = OCIInt(config_file="~/.oci/config")

    # Get Tenancy OCID
    oci_manager.get_tenancy_ocid()

    # Create User
    user = oci_manager.create_user(
        first_name="Britive", last_name="User", email="britive.user@example.com"
    )

    # Add API Key to User
    public_key_content = "YOUR_PUBLIC_KEY_CONTENT"
    oci_manager.add_api_key_to_user(
        user_id=user.id, public_key_content=public_key_content
    )

    # Create Group
    group = oci_manager.create_group(
        group_name="BritiveGroup", description="Group for Britive users"
    )

    # Assign User to Group
    oci_manager.assign_user_to_group(user_id=user.id, group_id=group.id)

    # Create Policy
    policy_statements = [
        "Allow group BritiveGroup to use users in tenancy",
        "Allow group BritiveGroup to use groups in tenancy",
        "Allow group BritiveGroup to inspect policies in tenancy",
        "Allow group BritiveGroup to inspect domains in tenancy",
    ]
    oci_manager.create_policy(
        policy_name="BritivePolicy",
        policy_statements=policy_statements,
        description="Policy for Britive group",
    )
