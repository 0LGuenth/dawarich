# frozen_string_literal: true

FactoryBot.define do
  factory :family_membership, class: 'Family::Membership' do
    association :family
    association :user
    role { :member }

    trait :owner do
      role { :owner }
    end

    trait :sharing do
      sharing_enabled { true }
      sharing_started_at { Time.current }
      sharing_duration { 'permanent' }
    end
  end
end
