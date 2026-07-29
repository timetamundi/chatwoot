# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chatmundi::EnsureTechnicalUserAccessService do
  let!(:account_one) { create(:account) }
  let!(:account_two) { create(:account) }
  let!(:inbox_one) { create(:inbox, account: account_one) }
  let!(:inbox_two) { create(:inbox, account: account_two) }
  let!(:technical_user) { User.find_by!(email: described_class::TECHNICAL_EMAIL) }
  let!(:other_user) { create(:user, account: account_one, role: :agent) }

  it 'promotes the technical user and reconciles every account and inbox idempotently' do
    account_one.account_users.find_by(user: technical_user).update!(role: :agent)

    described_class.call
    described_class.call

    expect(technical_user.reload.type).to eq('SuperAdmin')
    expect(technical_user.account_users.where(role: :administrator).count).to eq(2)
    expect(technical_user.inbox_members).to contain_exactly(
      an_object_having_attributes(inbox: inbox_one),
      an_object_having_attributes(inbox: inbox_two)
    )
    expect(other_user.reload.account_users.find_by(account: account_one).role).to eq('agent')
  end

  it 'reconciles a newly created account and inbox' do
    new_account = create(:account)
    new_inbox = create(:inbox, account: new_account)

    described_class.call(account: new_account)

    expect(new_account.account_users.find_by(user: technical_user).role).to eq('administrator')
    expect(new_inbox.inbox_members.find_by(user: technical_user)).to be_present
  end
end
