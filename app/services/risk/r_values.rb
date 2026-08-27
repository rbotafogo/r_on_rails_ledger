# frozen_string_literal: true

require "galaaz"

module Risk
  # Small unboxers for R::* results used by the ledger engines.
  module RValues
    module_function

    def scalar_f(obj)
      v = obj.respond_to?(:>>) ? (obj >> 0) : obj
      v = v.to_ruby if v.respond_to?(:to_ruby)
      Array(v).flatten.first.to_f
    end

    def scalar_s(obj)
      v = obj.respond_to?(:>>) ? (obj >> 0) : obj
      v = v.to_ruby if v.respond_to?(:to_ruby)
      Array(v).flatten.first.to_s
    end

    def float_array(obj)
      v = obj.respond_to?(:to_ruby) ? obj.to_ruby : (obj.respond_to?(:>>) ? (obj >> 0) : obj)
      Array(v).flatten.map(&:to_f)
    end

    def r_version_string
      scalar_s(R::Support.eval('paste(R.version$major, R.version$minor, sep = ".")'))
    end
  end
end
