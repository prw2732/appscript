#!/usr/local/bin/ruby

require "appscript"

module OSAX

	# Allows scripting additions (a.k.a. OSAXen) to be called from Ruby.
	
	######################################################################
	# PRIVATE
	######################################################################
	
	require "ae"
	require "kae"
	require "aem"
	
	#######
	# cache; stores osax paths and previously parsed terminology (if any) by osax name
	
	OSAXCache = {}
	OSAXNames = []
	
	se = Appscript.app.by_id('com.apple.systemevents')
	[se.system_domain, se.local_domain, se.user_domain].each do |domain|
		osaxen = domain.scripting_additions_folder.files[
				Appscript.its.file_type.eq('osax').or(Appscript.its.name_extension.eq('osax'))]
		osaxen.name.get.zip(osaxen.POSIX_path.get).each do |name, path|
			name = name.sub(/(?i)\.osax$/, '') # remove name extension, if any
			OSAXNames.push(name)
			OSAXCache[name.downcase] = [path, nil]
		end
	end
	OSAXNames.sort!.uniq!
	
	#######
	# modified AppData class
	
	class OSAXData < Appscript::AppData
	
		def initialize(constructor, identifier, terms)
			super(AEM::Application, constructor, identifier, terms)
		end
	
		def connect
			super
			begin
				@target.event('ascrgdut').send(60 * 60) # make sure target application has loaded event handlers for all installed OSAXen
			rescue AEM::CommandError => e
				if e.number != -1708 # ignore 'event not handled' error
					raise
				end
			end
		end
	
	end
	
	@_standard_additions = nil
	
	
	######################################################################
	# PUBLIC
	######################################################################
	
	def OSAX.scripting_additions
		# list names of all currently installed scripting additions
		return OSAXNames
	end
	
	def OSAX.osax(name=nil, app_name=nil)
		# Convenience method for creating a new ScriptingAddition instance.
		#	name : String | nil -- scripting addition's name; nil = 'StandardAdditions'
		#	app_name : String | nil -- target application's name/path, or nil for current application
		#	Result : ScriptingAddition
		#
		# If both arguments are nil, a ScriptingAddition object for StandardAdditions is created
		# and returned. This object is cached for efficiency and returned in subsequent calls;
		# thus clients can conveniently write (e.g):
		#
		#	osax.some_command
		#	osax.another_command
		#
		# instead of:
		#
		#	sa = osax
		#	sa.some_command
		#	sa.another_command
		#
		# without the additional overhead of creating a new ScriptingAddition object each time.
		#
		if name == nil and app_name == nil
			if @_standard_additions == nil
				@_standard_additions = ScriptingAddition.new('StandardAdditions')
			end
			addition = @_standard_additions
		else
			if name == nil
				name = 'StandardAdditions'
			end
			addition = ScriptingAddition.new(name)
			if app_name
				addition = addition.by_name(app_name)
			end
		end
		return addition
	end
	
	# allow methods to be included via 'include OSAX'
	
	def scripting_additions
		return OSAX.scripting_additions
	end
	
	def osax(*args)
		return OSAX.osax(*args)
	end
	
	#######
	
	class ScriptingAddition < Appscript::Reference
		# Represents a single scripting addition.
		
		def initialize(name, osax_data=nil)
			# name: string -- a scripting addition's name, e.g. "StandardAdditions";
			#	basically its filename minus the '.osax' suffix
			#
			# Note that name is case-insensitive and an '.osax' suffix is ignored if given.
			@_osax_name = name
			if not osax_data
				osax_name = name.downcase.sub(/(?i)\.osax$/, '')
				path, terms = OSAXCache[osax_name]
				if not path
					raise ArgumentError, "Scripting addition not found: #{name.inspect}"
				end
				if terms
					@_terms = terms
				else
					desc = AE.get_app_terminology(path).coerce(KAE::TypeAEList)
					@_terms = OSAXCache[osax_name][1] = \
							Terminology.tables_for_aetes(DefaultCodecs.unpack(desc))
				end
				osax_data = OSAXData.new(:current, nil, @_terms)
			end
			super(osax_data, AEM.app)
		end
		
		def to_s
			return "#<OSAX::ScriptingAddition name=#{@_osax_name.inspect} target=#{@AS_app_data.target.inspect}>"
		end
		
		alias_method :inspect, :to_s
		
		##
		
		def method_missing(name, *args)
			begin
				super
			rescue Appscript::CommandError => e
				if e.to_i == -1713 # 'No user interaction allowed' error (e.g. user tried to send a 'display dialog' command to a non-GUI ruby process), so convert the target process to a full GUI process and try again
					AE.transform_process_to_foreground_application
					activate
					super
				else
					raise
				end
			end
		end
		
		# A client-created scripting addition is automatically targetted at the current application.
		# Clients can specify another application as target by calling one of the following methods:
		
		def by_name(name)
			# name : string -- name or full path to application
			return ScriptingAddition.new(@_osax_name, 
					OSAXData.new(:by_path, FindApp.by_name(name), @_terms))
		end
		
		def by_id(id)
			# id : string -- bundle id of application
			return ScriptingAddition.new(@_osax_name, 
					OSAXData.new(:by_path, FindApp.by_id(id), @_terms))
		end
		
		def by_creator(creator)
			# creator : string -- four-character creator code of application
			return ScriptingAddition.new(@_osax_name, 
					OSAXData.new(:by_path, FindApp.by_creator(creator), @_terms))
		end
		
		def by_pid(pid)
			# pid : integer -- Unix process id
			return ScriptingAddition.new(@_osax_name, OSAXData.new(:by_pid, pid, @_terms))
		end
		
		def by_url(url)
			# url : string -- eppc URL of application
			return ScriptingAddition.new(@_osax_name, OSAXData.new(:by_url, url, @_terms))
		end
		
		def by_aem_app(aem_app)
			# aem_app : AEM::Application -- an AEM::Application instance
			return ScriptingAddition.new(@_osax_name, OSAXData.new(:by_aem_app, aem_app, @_terms))
		end
		
		def current
			return ScriptingAddition.new(@_osax_name, OSAXData.new(:current, nil, @_terms))
		end
	end
	
end