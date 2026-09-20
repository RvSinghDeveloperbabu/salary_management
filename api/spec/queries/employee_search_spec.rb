require "rails_helper"

RSpec.describe EmployeeSearch do
  let(:engineering) { create(:department, name: "Engineering") }
  let(:sales) { create(:department, name: "Sales") }
  let(:l1) { create(:job_level, name: "L1", rank: 1) }
  let(:l3) { create(:job_level, name: "L3", rank: 3) }

  def search(params = {}) = described_class.new(params).call

  describe "the sort allow-list" do
    # CLAUDE.md non-negotiable 4. Rails quotes values, not identifiers, so
    # this allow-list is the only thing between the sort parameter and
    # arbitrary SQL.
    it "rejects an arbitrary column name" do
      expect { search(sort: "password_digest") }
        .to raise_error(InvalidQueryParameter, /not a permitted value for sort/)
    end

    it "rejects a SQL fragment" do
      expect { search(sort: "employees.id; DROP TABLE employees") }
        .to raise_error(InvalidQueryParameter)
    end

    it "rejects a subquery attempt" do
      expect { search(sort: "(SELECT password_digest FROM users)") }
        .to raise_error(InvalidQueryParameter)
    end

    it "leaves the table intact after a rejected injection attempt" do
      create(:employee)

      expect { search(sort: "1; DROP TABLE employees; --") }
        .to raise_error(InvalidQueryParameter)
      expect(Employee.count).to eq(1)
    end

    it "accepts every documented sort key" do
      described_class::SORTABLE.each_key do |key|
        expect { search(sort: key) }.not_to raise_error
      end
    end

    it "rejects an arbitrary sort direction" do
      expect { search(direction: "asc; DELETE FROM employees") }
        .to raise_error(InvalidQueryParameter, /direction/)
    end

    it "accepts asc and desc in any case" do
      expect { search(direction: "DESC") }.not_to raise_error
    end

    it "names the permitted values in the error, so the client can recover" do
      error = begin
        search(sort: "nonsense")
      rescue InvalidQueryParameter => e
        e
      end

      expect(error.message).to include("name", "hired_on", "salary")
      expect(error.details).to match(sort: [ a_string_including("must be one of") ])
    end

    it "is frozen" do
      expect(described_class::SORTABLE).to be_frozen
    end
  end

  describe "filtering" do
    let!(:ada) do
      create(:employee, first_name: "Ada", last_name: "Lovelace", email: "ada@example.com",
        employee_code: "EMP-00001", department: engineering, job_level: l3, country_code: "GB")
    end
    let!(:grace) do
      create(:employee, first_name: "Grace", last_name: "Hopper", email: "grace@example.com",
        employee_code: "EMP-00002", department: sales, job_level: l1, country_code: "US")
    end
    let!(:leaver) do
      create(:employee, :terminated, first_name: "Alan", last_name: "Turing",
        employee_code: "EMP-00003",
        department: engineering, job_level: l3, country_code: "GB")
    end

    it "returns everyone when unfiltered" do
      expect(search.records).to contain_exactly(ada, grace, leaver)
    end

    it "filters by status" do
      expect(search(status: "active").records).to contain_exactly(ada, grace)
    end

    it "filters by department" do
      expect(search(department_id: engineering.id).records).to contain_exactly(ada, leaver)
    end

    it "filters by job level" do
      expect(search(job_level_id: l1.id).records).to contain_exactly(grace)
    end

    it "filters by country, case insensitively" do
      expect(search(country_code: "gb").records).to contain_exactly(ada, leaver)
    end

    it "combines filters" do
      result = search(status: "active", department_id: engineering.id, country_code: "GB")

      expect(result.records).to contain_exactly(ada)
    end

    it "ignores blank filters rather than matching nothing" do
      expect(search(department_id: "", country_code: nil, q: "  ").records).to have_attributes(size: 3)
    end

    it "rejects an unknown status" do
      expect { search(status: "on_holiday") }.to raise_error(InvalidQueryParameter, /status/)
    end

    describe "search term" do
      it "matches a last name, case insensitively" do
        expect(search(q: "lovelace").records).to contain_exactly(ada)
      end

      it "matches a first name" do
        expect(search(q: "Grace").records).to contain_exactly(grace)
      end

      it "matches an email address" do
        expect(search(q: "ada@").records).to contain_exactly(ada)
      end

      it "matches an employee code" do
        expect(search(q: "EMP-00002").records).to contain_exactly(grace)
      end

      it "matches a partial term" do
        expect(search(q: "ove").records).to contain_exactly(ada)
      end

      it "returns nothing for a term that matches nobody" do
        expect(search(q: "zzzzz").records).to be_empty
      end

      # Without escaping, a literal % would become a wildcard matching
      # everyone, which is a surprising result rather than an empty one.
      it "treats % as a literal, not a wildcard" do
        expect(search(q: "%").records).to be_empty
      end

      it "treats _ as a literal, not a single-character wildcard" do
        expect(search(q: "_").records).to be_empty
      end
    end
  end

  describe "sorting" do
    let!(:third) { create(:employee, last_name: "Clarke", hired_on: 1.year.ago.to_date) }
    let!(:first) { create(:employee, last_name: "Adams", hired_on: 3.years.ago.to_date) }
    let!(:second) { create(:employee, last_name: "Brown", hired_on: 2.years.ago.to_date) }

    it "sorts by name ascending by default" do
      expect(search.records.to_a).to eq([ first, second, third ])
    end

    it "sorts by name descending" do
      expect(search(direction: "desc").records.to_a).to eq([ third, second, first ])
    end

    it "sorts by hire date" do
      expect(search(sort: "hired_on").records.to_a).to eq([ first, second, third ])
    end

    it "sorts by department name across a join" do
      a = create(:employee, department: create(:department, name: "AAA"))
      result = search(sort: "department")

      expect(result.records.first).to eq(a)
    end

    it "sorts by level rank rather than level name" do
      # L10 must sort after L2, which it would not if ordering on the label.
      junior = create(:employee, job_level: create(:job_level, name: "L2", rank: 2))
      senior = create(:employee, job_level: create(:job_level, name: "L10", rank: 10))

      ranked = search(sort: "level").records.to_a

      expect(ranked.index(junior)).to be < ranked.index(senior)
    end

    it "sorts by current salary across the denormalised pointer" do
      rich = create(:employee)
      poor = create(:employee)
      Salaries::RecordChange.new(employee: rich, amount_cents: 20_000_000, currency: "USD",
        effective_from: 1.year.ago.to_date, change_reason: "hire").call
      Salaries::RecordChange.new(employee: poor, amount_cents: 5_000_000, currency: "USD",
        effective_from: 1.year.ago.to_date, change_reason: "hire").call

      ordered = search(sort: "salary", direction: "desc").records.to_a

      expect(ordered.index(rich)).to be < ordered.index(poor)
    end

    describe "sorting by salary across currencies" do
      # Amounts are stored in local currency. Ordering on the raw integer
      # would rank 2,400,000.00 INR (about 28,800 USD) above 100,000.00 USD
      # and tell the HR manager the lowest-paid person is the highest.
      let!(:american) { create(:employee, country_code: "US") }
      let!(:indian) { create(:employee, :in_india) }

      before do
        create(:exchange_rate, :identity, rate_on: Rates::SNAPSHOT_DATE)
        create(:exchange_rate, base_currency: "INR", quote_currency: "USD",
          rate_ppm: 12_000, rate_on: Rates::SNAPSHOT_DATE)

        Salaries::RecordChange.new(employee: american, amount_cents: 10_000_000,
          currency: "USD", effective_from: 1.year.ago.to_date, change_reason: "hire").call
        Salaries::RecordChange.new(employee: indian, amount_cents: 240_000_000,
          currency: "INR", effective_from: 1.year.ago.to_date, change_reason: "hire").call
      end

      it "ranks the higher real salary first, not the larger integer" do
        ordered = search(sort: "salary", direction: "desc").records.to_a

        expect(ordered.index(american)).to be < ordered.index(indian)
      end

      it "ranks the lower real salary first when ascending" do
        ordered = search(sort: "salary", direction: "asc").records.to_a

        expect(ordered.index(indian)).to be < ordered.index(american)
      end

      # A currency with no seeded rate is a data gap to notice, not a reason
      # to drop someone out of the directory entirely.
      it "still returns an employee whose currency has no rate" do
        orphan = create(:employee, country_code: "BR")
        Salaries::RecordChange.new(employee: orphan, amount_cents: 50_000_000,
          currency: "BRL", effective_from: 1.year.ago.to_date, change_reason: "hire").call

        expect(search(sort: "salary").records).to include(orphan)
      end
    end

    # Offset pagination is only correct over a total order. Without a unique
    # tiebreaker, rows sharing a sort value can swap between queries, so a
    # row shown on page 1 can reappear or vanish on page 2.
    it "breaks ties on id, so paging is stable" do
      create_list(:employee, 5, last_name: "Same")

      page_one = described_class.new(sort: "name", per_page: 3, page: 1).call.records.map(&:id)
      page_two = described_class.new(sort: "name", per_page: 3, page: 2).call.records.map(&:id)

      expect(page_one.size).to eq(3)
      expect(page_two.size).to eq(3)
      expect(page_one & page_two).to be_empty
    end
  end

  describe "pagination" do
    before { create_list(:employee, 7) }

    it "defaults to 50 per page" do
      expect(search.per_page).to eq(50)
    end

    it "reports the total count independent of the page size" do
      expect(search(per_page: 2).total_count).to eq(7)
    end

    it "reports the number of pages" do
      expect(search(per_page: 2).total_pages).to eq(4)
    end

    it "returns the requested page" do
      expect(search(per_page: 2, page: 2).records.size).to eq(2)
    end

    it "returns a partial final page" do
      expect(search(per_page: 2, page: 4).records.size).to eq(1)
    end

    it "treats page 0 and negative pages as page 1" do
      expect(search(page: 0).page).to eq(1)
      expect(search(page: -5).page).to eq(1)
    end

    # Otherwise a client can ask for the whole table in one request.
    it "caps per_page so the whole table cannot be requested at once" do
      expect(search(per_page: 100_000).per_page).to eq(described_class::MAX_PER_PAGE)
    end

    it "falls back to the default for a non-numeric per_page" do
      expect(search(per_page: "lots").per_page).to eq(50)
    end
  end

  describe "query count" do
    # docs/architecture.md: a 50-row page is a handful of queries, not one
    # per row. This is the spec that would catch an N+1 being reintroduced.
    it "loads a page and its associations in a fixed number of queries" do
      create_list(:employee, 25)

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
        queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end

      result = described_class.new(per_page: 25).call
      result.records.each { |e| [ e.department.name, e.job_level.name, e.current_salary ] }

      ActiveSupport::Notifications.unsubscribe(subscriber)

      # 1 count + 1 employees + 3 preloads.
      expect(queries.size).to be <= 6
    end
  end
end
